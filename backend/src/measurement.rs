use chrono::serde::ts_seconds;
use chrono::{DateTime, TimeZone, Utc};
#[cfg(test)]
use influxdb::Query;
use influxdb::{InfluxDbWriteable, WriteQuery};
use serde::{Deserialize, Serialize};

#[derive(InfluxDbWriteable, Serialize, Deserialize, Debug, Clone)]
pub struct GlucoseMeasurement {
    #[serde(with = "ts_seconds")]
    pub time: DateTime<Utc>,
    pub value: f64,
}

/// One app-owned sample. `id` is retained as diagnostic provenance. Influx point
/// identity remains measurement + timestamp: retries overwrite the same point,
/// and two app records for the same sample time deliberately coalesce. This
/// matches the server's existing one-value-per-timestamp Viewer data model while
/// avoiding an unbounded series tag for every reading.
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
pub struct UploadedGlucoseMeasurement {
    pub id: String,
    #[serde(with = "ts_seconds")]
    pub time: DateTime<Utc>,
    pub value: f64,
}

impl UploadedGlucoseMeasurement {
    pub fn validate(&self) -> Result<(), &'static str> {
        if self.id.is_empty()
            || self.id.len() > 128
            || !self
                .id
                .bytes()
                .all(|byte| byte.is_ascii_alphanumeric() || byte == b'-')
        {
            return Err("id must contain 1-128 letters, digits, or hyphens");
        }
        if !self.value.is_finite() || !(1.0..=33.3).contains(&self.value) {
            return Err("value must be a finite mmol/L value from 1.0 through 33.3");
        }
        let now = Utc::now().timestamp();
        if self.time.timestamp() < 946_684_800 || self.time.timestamp() > now + 86_400 {
            return Err("time is outside the supported range");
        }
        Ok(())
    }

    pub fn to_write_query(&self) -> WriteQuery {
        WriteQuery::new(self.time.into(), "bloodglucose")
            .add_field("source_id", self.id.clone())
            .add_field("value", self.value)
    }
}

impl GlucoseMeasurement {
    pub fn to_write_query(&self) -> WriteQuery {
        WriteQuery::new(self.time.into(), "bloodglucose").add_field("value", self.value)
    }
}

#[test]
pub fn test_json_serialization() {
    let fixed_time = Utc.with_ymd_and_hms(2025, 3, 22, 12, 0, 0).unwrap();

    let data = vec![GlucoseMeasurement {
        time: fixed_time,
        value: 5.5,
    }];

    let json = serde_json::to_string(&data).unwrap();
    assert_eq!(json, r#"[{"time":1742644800,"value":5.5}]"#);
}

#[test]
fn uploaded_measurement_validation_and_identity() {
    let sample = UploadedGlucoseMeasurement {
        id: "84a146be-1a63-4d09-8f8d-704da981f6a4".into(),
        time: Utc.with_ymd_and_hms(2025, 3, 22, 12, 0, 0).unwrap(),
        value: 5.5,
    };
    assert_eq!(sample.validate(), Ok(()));
    let first = sample.to_write_query().build().unwrap().get();
    let second = sample.to_write_query().build().unwrap().get();
    assert_eq!(
        first, second,
        "a retry must retain identical Influx identity"
    );

    let mut invalid = sample.clone();
    invalid.id = "token=secret".into();
    assert!(invalid.validate().is_err());
    invalid = sample;
    invalid.value = 0.0;
    assert!(invalid.validate().is_err());
}
