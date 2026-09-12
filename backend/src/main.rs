mod application_settings;
mod database;
mod librelink;
mod measurement;
mod webserver;

use crate::application_settings::ApplicationSettings;
use crate::database::{get_last_entries, InfluxConnection};
use crate::librelink::LibreLinkSyncRuntime;
use anyhow::{anyhow, Context, Result};
use config::{Config, Environment, File};
use librelink_client::client::{Credentials, LibreLinkClient};
use log;
use log::LevelFilter;
use serde::{Deserialize, Serialize};
use simple_logger;
use simple_logger::SimpleLogger;
use std::env;
use std::path::Path;
use std::sync::Arc;
use tokio;
use warp::Filter;

#[tokio::main]
async fn main() -> Result<()> {
    SimpleLogger::new()
        .with_level(LevelFilter::Trace)
        .with_module_level("hyper", LevelFilter::Warn)
        .with_module_level("warp", LevelFilter::Warn)
        .with_module_level("reqwest", LevelFilter::Warn)
        .with_module_level("tracing", LevelFilter::Warn)
        .init()
        .expect("Failed to init logger");

    log::info!("Starting GlucoScope v{}", env!("CARGO_PKG_VERSION"));

    let settings = ApplicationSettings::load().context("Failed to load settings")?;

    let influx_client = InfluxConnection::new(
        &settings.influx_url,
        &settings.influx_db,
        &settings.influx_token,
    );

    if settings.librelink_username.is_some() || settings.librelink_password.is_some() {
        start_libre_link_sync(influx_client.clone(), &settings)
            .await
            .context("Failed to connect to LibreLink")?;
    } else {
        log::info!("LibreLink credentials are not configured; direct uploads remain available");
    }
    webserver::start_server(influx_client.clone(), settings.api_token);

    tokio::signal::ctrl_c()
        .await
        .expect("Failed to listen for ctrl-c");
    Ok(())
}

pub async fn start_libre_link_sync(
    influx_client: Arc<InfluxConnection>,
    settings: &ApplicationSettings,
) -> Result<()> {
    log::trace!("Authenticating with LibreLink Up…");

    let username = settings
        .librelink_username
        .as_ref()
        .ok_or_else(|| anyhow!("librelink_username and librelink_password must be set together"))?;
    let password = settings
        .librelink_password
        .as_ref()
        .ok_or_else(|| anyhow!("librelink_username and librelink_password must be set together"))?;
    let realm = settings.librelink_realm.as_deref().unwrap_or("EU");

    let client = LibreLinkClient::new(
        Credentials {
            username: username.clone(),
            password: password.clone(),
        },
        Some(realm.to_owned()),
    )
    .await
    .map_err(|e| anyhow!("{}", e))?;

    tokio::spawn(async move {
        let mut runtime = LibreLinkSyncRuntime::new(influx_client, client);
        runtime.start().await;
    });

    Ok(())
}

//
// #[tokio::test]
// pub async fn test_libre_runtime() {
//     simple_logger::init().expect("Failed to init logger");
//     let influx_client = InfluxConnection::new(
//         "http://localhost:8086",
//         "sugarscope",
//         "hCR1XAF7FJcUHiutI-ahzsxI9ESlOa1GsTGfju0KxcW-TZTlLPMPR9tP8C8_rtme2pn7qRNIYMlHZrcEGBs7yA==",
//     );
//
//     start_libre_link_sync(influx_client).await;
//     tokio::time::sleep(tokio::time::Duration::from_secs(60)).await;
// }
