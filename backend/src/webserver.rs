use crate::database::{get_last_entries, InfluxConnection};
use serde_json::json;
use std::sync::Arc;
use warp::filters::BoxedFilter;
use warp::header::value;
use warp::http::StatusCode;
use warp::{Filter, Rejection, Reply};

pub fn start_server(connection: Arc<InfluxConnection>, api_token: Option<String>) {
    tokio::spawn(async move {
        log::info!("Starting server @ 0.0.0.0:9090");

        let conn_filter = warp::any().map(move || connection.clone());
        let auth_filter = with_auth(api_token.clone());

        let base_path = warp::path("api").and(warp::path("s1")).and(auth_filter);

        // GET /api/s1/status
        let status_route = base_path
            .clone()
            .and(warp::path("status"))
            .and(warp::get())
            .map(|| warp::reply::json(&json!({ "status": "ok" })));

        // GET /api/s1/entries/last?hours=..&window=..
        let graph_route = base_path
            .clone()
            .and(warp::path("entries").and(warp::path("last")))
            .and(warp::get())
            .and(warp::query::<QueryParams>())
            .and(conn_filter)
            .and_then(handle_latest_request);

        let routes = status_route
            .or(graph_route)
            .recover(handle_rejection)
            .with(warp::cors().allow_any_origin());

        warp::serve(routes).run(([0, 0, 0, 0], 9090)).await;
    });
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
    } else if let Some(api) = err.find::<ApiError>() {
        Ok(warp::reply::with_status(
            api.message,
            StatusCode::INTERNAL_SERVER_ERROR,
        ))
    } else {
        Ok(warp::reply::with_status("Not Found", StatusCode::NOT_FOUND))
    }
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
