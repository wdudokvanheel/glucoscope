use crate::database::{get_last_entries, save_uploaded_measurement, InfluxConnection};
use crate::measurement::UploadedGlucoseMeasurement;
use serde_json::json;
use std::sync::Arc;
use warp::filters::BoxedFilter;
use warp::http::StatusCode;
use warp::{Filter, Rejection, Reply};

pub fn start_server(connection: Arc<InfluxConnection>, api_token: Option<String>) {
    tokio::spawn(async move {
        log::info!("Starting server @ 0.0.0.0:9090");

        let routes = routes(connection, api_token);

        warp::serve(routes).run(([0, 0, 0, 0], 9090)).await;
    });
}

fn routes(
    connection: Arc<InfluxConnection>,
    api_token: Option<String>,
) -> impl Filter<Extract = (impl Reply,), Error = Rejection> + Clone {
    let uploads_enabled = api_token.is_some();
    let conn_filter = warp::any().map(move || connection.clone());
    let base_path = warp::path("api")
        .and(warp::path("s1"))
        .and(with_auth(api_token.clone()));
    // Writes are never anonymous. A server without api_token keeps its legacy
    // public read behavior, but rejects uploads until the operator configures one.
    let upload_base_path = warp::path("api")
        .and(warp::path("s1"))
        .and(with_required_auth(api_token));

    let status_route = base_path
        .clone()
        .and(warp::path("status"))
        .and(warp::path::end())
        .and(warp::get())
        .map(move || {
            warp::reply::json(&json!({
                "status": "ok",
                "uploadsEnabled": uploads_enabled
            }))
        });

    let graph_route = base_path
        .clone()
        .and(warp::path("entries").and(warp::path("last")))
        .and(warp::path::end())
        .and(warp::get())
        .and(warp::query::<QueryParams>())
        .and(conn_filter.clone())
        .and_then(handle_latest_request);

    // POST /api/s1/entries. The small explicit cap is enough for one reading and
    // prevents this public route from buffering arbitrary request bodies.
    let upload_route = upload_base_path
        .and(warp::path("entries"))
        .and(warp::path::end())
        .and(warp::post())
        .and(warp::body::content_length_limit(4 * 1024))
        .and(warp::body::json::<UploadedGlucoseMeasurement>())
        .and(conn_filter)
        .and_then(handle_upload_request);

    status_route
        .or(graph_route)
        .or(upload_route)
        .recover(handle_rejection)
        .with(warp::cors().allow_any_origin())
}

fn with_required_auth(api_token: Option<String>) -> BoxedFilter<()> {
    match api_token {
        Some(token) => with_auth(Some(token)),
        None => warp::any()
            .and_then(|| async { Err::<(), Rejection>(warp::reject::custom(Unauthorized)) })
            .untuple_one()
            .boxed(),
    }
}

fn with_auth(api_token: Option<String>) -> BoxedFilter<()> {
    match api_token {
        Some(token) => {
            let expected = format!("Bearer {}", token);

            warp::header::optional::<String>("authorization")
                .and_then(move |header: Option<String>| {
                    let expected = expected.clone();
                    async move {
                        match header {
                            Some(value) if value == expected => Ok(()),
                            _ => Err(warp::reject::custom(Unauthorized)),
                        }
                    }
                })
                .untuple_one()
                .boxed()
        }

        None => warp::any()
            .and_then(|| async { Ok::<(), Rejection>(()) })
            .untuple_one()
            .boxed(),
    }
}

async fn handle_rejection(err: Rejection) -> Result<impl Reply, std::convert::Infallible> {
    if err.find::<Unauthorized>().is_some() {
        Ok(warp::reply::with_status(
            "Unauthorized",
            StatusCode::UNAUTHORIZED,
        ))
    } else if let Some(validation) = err.find::<InvalidUpload>() {
        Ok(warp::reply::with_status(
            validation.message,
            StatusCode::BAD_REQUEST,
        ))
    } else if err.find::<warp::reject::PayloadTooLarge>().is_some() {
        Ok(warp::reply::with_status(
            "Payload too large",
            StatusCode::PAYLOAD_TOO_LARGE,
        ))
    } else if err
        .find::<warp::filters::body::BodyDeserializeError>()
        .is_some()
    {
        Ok(warp::reply::with_status(
            "Invalid JSON body",
            StatusCode::BAD_REQUEST,
        ))
    } else if let Some(api) = err.find::<ApiError>() {
        Ok(warp::reply::with_status(
            api.message,
            StatusCode::INTERNAL_SERVER_ERROR,
        ))
    } else {
        Ok(warp::reply::with_status("Not Found", StatusCode::NOT_FOUND))
    }
}

async fn handle_upload_request(
    measurement: UploadedGlucoseMeasurement,
    connection: Arc<InfluxConnection>,
) -> Result<impl warp::Reply, warp::Rejection> {
    measurement
        .validate()
        .map_err(|message| warp::reject::custom(InvalidUpload { message }))?;
    save_uploaded_measurement(&connection, &measurement)
        .await
        .map_err(|_| warp::reject::custom(ApiError::database_error()))?;
    Ok(warp::reply::with_status(
        warp::reply::json(&json!({ "saved": measurement.id })),
        StatusCode::CREATED,
    ))
}

#[derive(serde::Deserialize)]
struct QueryParams {
    hours: Option<u32>,
    window: Option<u32>,
}

async fn handle_latest_request(
    params: QueryParams,
    connection: Arc<InfluxConnection>,
) -> Result<impl warp::Reply, warp::Rejection> {
    let hours = params.hours.unwrap_or(12);
    let window = params.window.unwrap_or(5);

    match get_last_entries(&connection, hours as i32, window as i32).await {
        Ok(data) => Ok(warp::reply::json(&data)),
        Err(_) => Err(warp::reject::custom(ApiError::database_error())),
    }
}

#[derive(Debug)]
struct ApiError {
    message: &'static str,
}

impl warp::reject::Reject for ApiError {}

impl ApiError {
    fn database_error() -> Self {
        ApiError {
            message: "Database error",
        }
    }
}

#[derive(Debug)]
struct Unauthorized;
impl warp::reject::Reject for Unauthorized {}

#[derive(Debug)]
struct InvalidUpload {
    message: &'static str,
}
impl warp::reject::Reject for InvalidUpload {}

#[cfg(test)]
mod tests {
    use super::*;

    fn connection() -> Arc<InfluxConnection> {
        InfluxConnection::new("http://127.0.0.1:1", "test", "test")
    }

    #[tokio::test]
    async fn upload_requires_authentication_before_processing_body() {
        let api = routes(connection(), Some("correct-token".into()));
        let response = warp::test::request()
            .method("POST")
            .path("/api/s1/entries")
            .json(&json!({"id":"reading-1","time":1742644800,"value":5.5}))
            .reply(&api)
            .await;
        assert_eq!(response.status(), StatusCode::UNAUTHORIZED);
    }

    #[tokio::test]
    async fn upload_rejects_invalid_values_before_database_access() {
        let api = routes(connection(), Some("correct-token".into()));
        let response = warp::test::request()
            .method("POST")
            .path("/api/s1/entries")
            .header("authorization", "Bearer correct-token")
            .json(&json!({"id":"reading-1","time":1742644800,"value":0}))
            .reply(&api)
            .await;
        assert_eq!(response.status(), StatusCode::BAD_REQUEST);
        assert_eq!(
            response.body(),
            "value must be a finite mmol/L value from 1.0 through 33.3"
        );
    }

    #[tokio::test]
    async fn tokenless_legacy_server_remains_read_only() {
        let api = routes(connection(), None);
        let status = warp::test::request()
            .path("/api/s1/status")
            .reply(&api)
            .await;
        assert_eq!(status.status(), StatusCode::OK);
        let status_body: serde_json::Value = serde_json::from_slice(status.body()).unwrap();
        assert_eq!(status_body["uploadsEnabled"], false);
        let upload = warp::test::request()
            .method("POST")
            .path("/api/s1/entries")
            .json(&json!({"id":"reading-1","time":1742644800,"value":5.5}))
            .reply(&api)
            .await;
        assert_eq!(upload.status(), StatusCode::UNAUTHORIZED);
    }

    #[tokio::test]
    async fn status_uses_the_same_bearer_authentication() {
        let api = routes(connection(), Some("correct-token".into()));
        let denied = warp::test::request()
            .path("/api/s1/status")
            .reply(&api)
            .await;
        assert_eq!(denied.status(), StatusCode::UNAUTHORIZED);
        let allowed = warp::test::request()
            .path("/api/s1/status")
            .header("authorization", "Bearer correct-token")
            .reply(&api)
            .await;
        assert_eq!(allowed.status(), StatusCode::OK);
        let status_body: serde_json::Value = serde_json::from_slice(allowed.body()).unwrap();
        assert_eq!(status_body["uploadsEnabled"], true);
    }
}
