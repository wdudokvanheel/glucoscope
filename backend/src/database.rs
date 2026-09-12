use crate::measurement::{GlucoseMeasurement, UploadedGlucoseMeasurement};
use anyhow::Result;
use chrono::{DateTime, Utc};
use influxdb::{Client, InfluxDbWriteable, ReadQuery};
use serde::{Deserialize, Serialize};
use std::sync::Arc;

pub async fn get_last_entries(
    connection: &InfluxConnection,
    hours: i32,
    window: i32,
) -> Result<Vec<GlucoseMeasurement>> {
    let client = connection.open_connection();

    let query = ReadQuery::new(format!(
        "SELECT mean(value) AS value FROM bloodglucose
        WHERE time > now() - {}h
        GROUP BY time({}m) FILL(previous)",
        hours, window
    ));

    let values: Vec<_> = client
        .json_query(query)
        .await?
        .deserialize_next::<InfluxGlucoseMeasurement>()?
        .series
        .into_iter()
        .flat_map(|series| series.values)
        .filter_map(|igm| {
            igm.value.map(|value| GlucoseMeasurement {
                time: igm.time,
                value,
            })
        })
        .collect();

    Ok(values)
}

pub async fn save_measurement(
    connection: &InfluxConnection,
    measurement: &GlucoseMeasurement,
) -> Result<()> {
    let client = connection.open_connection();
    client.query(&measurement.to_write_query()).await?;
    Ok(())
}

pub async fn save_uploaded_measurement(
    connection: &InfluxConnection,
    measurement: &UploadedGlucoseMeasurement,
) -> Result<()> {
    let client = connection.open_connection();
    client.query(&measurement.to_write_query()).await?;
    Ok(())
}

#[derive(Debug, Clone)]
pub struct InfluxConnection {
    url: String,
    database: String,
    token: String,
}

impl InfluxConnection {
    pub fn new(url: &str, database: &str, token: &str) -> Arc<InfluxConnection> {
        Arc::new(Self {
            url: url.to_string(),
            database: database.to_string(),
            token: token.to_string(),
        })
    }

    pub fn open_connection(&self) -> Client {
        Client::new(&self.url, &self.database).with_token(&self.token)
    }
}

#[derive(InfluxDbWriteable, Serialize, Deserialize, Debug, Clone)]
pub struct InfluxGlucoseMeasurement {
    pub time: DateTime<Utc>,
    pub value: Option<f64>,
}

#[tokio::test]
async fn test_get_12h_measurements() {
    let connection = InfluxConnection::new(
        "http://localhost:8086",
        "sugarscope",
        "hCR1XAF7FJcUHiutI-ahzsxI9ESlOa1GsTGfju0KxcW-TZTlLPMPR9tP8C8_rtme2pn7qRNIYMlHZrcEGBs7yA==",
    );

    let measurements = get_last_entries(&connection, 12, 5)
        .await
        .expect("Failed to get last 12h values");

    for measurement in measurements {
        println!("{}: {}", measurement.time, measurement.value);
    }
}
