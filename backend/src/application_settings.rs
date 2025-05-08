use anyhow::Result;
use config::builder::DefaultState;
use config::{Config, ConfigBuilder, Environment, File};
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

#[derive(Debug, Serialize, Deserialize)]
pub struct ApplicationSettings {
    pub librelink_username: String,
    pub librelink_password: String,
    pub librelink_realm: String,
    pub influx_url: String,
    pub influx_db: String,
    pub influx_token: String,
    pub api_token: Option<String>,
}

impl ApplicationSettings {
    pub fn load() -> anyhow::Result<Self> {
        let mut config_builder: Option<ConfigBuilder<DefaultState>> = None;

        // Check for a user-specified config file from the CARECHORDS_CONF environment variable
        if let Ok(custom_conf) = env::var("SUGARSCOPE_CONF") {
            let path = Path::new(&custom_conf);
            if path.exists() {
                config_builder = Some(
                    Config::builder().add_source(File::with_name(&custom_conf).required(true)),
                );
            } else {
                anyhow::bail!(
                    "The configuration file specified in SUGARSCOPE_CONF does not exist: {}",
                    custom_conf
                );
            }
        } else {
            // Search in standard locations if SUGARSCOPE_CONF is not set
            let config_paths = [
                "/sugarscope.toml",
                "/etc/sugarscope.toml",
                "/usr/local/etc/sugarscope.toml",
                "/opt/sugarscope/sugarscope.toml",
            ];

            for path in &config_paths {
                if Path::new(path).exists() {
                    config_builder =
                        Some(Config::builder().add_source(File::with_name(path).required(true)));
                }
            }
        }

        if let Some(mut config_builder) = config_builder {
            // config_builder = config_builder.add_source(Environment::with_prefix("SUGARSCOPE"));
            let settings: ApplicationSettings = config_builder.build()?.try_deserialize()?;

            let toml_str = toml::to_string_pretty(&settings)
                .expect("Failed to convert settings to TOML format");
            log::info!("Running with settings:\n{}", toml_str);
            Ok(settings)
        } else {
            Err(anyhow::anyhow!("Failed to find any configuration file"))
        }
    }
}
