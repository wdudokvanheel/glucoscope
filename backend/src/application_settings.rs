use config::builder::DefaultState;
use config::{Config, ConfigBuilder, File};
use log;
use serde::{Deserialize, Serialize};
use std::env;
use std::path::Path;

#[derive(Debug, Serialize, Deserialize)]
pub struct ApplicationSettings {
    pub librelink_username: Option<String>,
    pub librelink_password: Option<String>,
    pub librelink_realm: Option<String>,
    pub influx_url: String,
    pub influx_db: String,
    pub influx_token: String,
    pub api_token: Option<String>,
}

impl ApplicationSettings {
    pub fn load() -> anyhow::Result<Self> {
        let mut config_builder: Option<ConfigBuilder<DefaultState>> = None;

        // Check for a user-specified config file from the CARECHORDS_CONF environment variable
        if let Ok(custom_conf) = env::var("GLUCOSCOPE_CONF") {
            let path = Path::new(&custom_conf);
            if path.exists() {
                config_builder = Some(
                    Config::builder().add_source(File::with_name(&custom_conf).required(true)),
                );
            } else {
                anyhow::bail!(
                    "The configuration file specified in GLUCOSCOPE_CONF does not exist: {}",
                    custom_conf
                );
            }
        } else {
            // Search in standard locations if GLUCOSCOPE_CONF is not set
            let config_paths = [
                "/glucoscope.toml",
                "/etc/glucoscope.toml",
                "/usr/local/etc/glucoscope.toml",
                "/opt/glucoscope/glucoscope.toml",
            ];

            for path in &config_paths {
                if Path::new(path).exists() {
                    config_builder =
                        Some(Config::builder().add_source(File::with_name(path).required(true)));
                }
            }
        }

        if let Some(config_builder) = config_builder {
            // config_builder = config_builder.add_source(Environment::with_prefix("SUGARSCOPE"));
            let settings: ApplicationSettings = config_builder.build()?.try_deserialize()?;

            log::info!(
                "Loaded configuration (LibreLink: {}, API auth: {})",
                if settings.librelink_username.is_some() {
                    "configured"
                } else {
                    "disabled"
                },
                if settings.api_token.is_some() {
                    "configured"
                } else {
                    "disabled"
                }
            );
            Ok(settings)
        } else {
            Err(anyhow::anyhow!("Failed to find any configuration file"))
        }
    }
}
