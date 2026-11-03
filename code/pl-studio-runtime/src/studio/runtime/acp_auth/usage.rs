//! Antigravity 固定发行 `/usage` 报告的额度段解析。
//!
//! 这里只接受官方发行已确认的 Markdown 形态，并且只读取 `### Quota Limits` 段。任何未知、
//! 畸形、越界或混合特殊状态都整体失败，不发布部分额度。

use pl_protocol::studio::{
    AcpQuotaGroup, AcpQuotaLimit, AcpQuotaRemaining, AcpUsageFailureCode, AcpUsageState,
};

const SECTION: &str = "### Quota Limits";
const MAX_GROUPS: usize = 64;
const MAX_LIMITS_PER_GROUP: usize = 64;
const MAX_TOTAL_LIMITS: usize = 256;
const MAX_NAME_BYTES: usize = 256;
const MAX_LINE_BYTES: usize = 1024;

pub(super) fn map_report(report: pl_acp::auth::UsageReport) -> AcpUsageState {
    match report {
        pl_acp::auth::UsageReport::Text(text) => parse(&text).unwrap_or(AcpUsageState::Failed {
            code: AcpUsageFailureCode::InvalidResponse,
        }),
        pl_acp::auth::UsageReport::Failed(failure) => AcpUsageState::Failed {
            code: match failure {
                pl_acp::auth::UsageFailure::Query => AcpUsageFailureCode::Query,
                pl_acp::auth::UsageFailure::Timeout => AcpUsageFailureCode::Timeout,
                pl_acp::auth::UsageFailure::Transport => AcpUsageFailureCode::Transport,
                pl_acp::auth::UsageFailure::ResourceLimit => AcpUsageFailureCode::ResourceLimit,
            },
        },
    }
}

fn parse(report: &str) -> Result<AcpUsageState, ()> {
    let lines: Vec<&str> = report.lines().collect();
    if lines.iter().any(|line| line.len() > MAX_LINE_BYTES) {
        return Err(());
    }
    let mut sections = lines
        .iter()
        .enumerate()
        .filter(|(_, line)| **line == SECTION);
    let Some((start, _)) = sections.next() else {
        return Err(());
    };
    if sections.next().is_some() {
        return Err(());
    }
    let end = lines[start + 1..]
        .iter()
        .position(|line| line.starts_with("### "))
        .map_or(lines.len(), |offset| start + 1 + offset);
    let body: Vec<&str> = lines[start + 1..end]
        .iter()
        .copied()
        .filter(|line| !line.trim().is_empty())
        .collect();
    match body.as_slice() {
        ["- Not applicable for current authentication method."] => {
            return Ok(AcpUsageState::NotApplicable);
        }
        ["- data not available yet"] => return Ok(AcpUsageState::Unavailable),
        ["- No quota limits reported."] => {
            return Ok(AcpUsageState::Ready { groups: Vec::new() });
        }
        [line]
            if line.starts_with("- Unable to retrieve quota status (") && line.ends_with(')') =>
        {
            return Ok(AcpUsageState::Failed {
                code: AcpUsageFailureCode::Query,
            });
        }
        [] => return Err(()),
        _ => {}
    }

    let mut groups = Vec::new();
    let mut total_limits = 0usize;
    let mut cursor = 0usize;
    while cursor < body.len() {
        if groups.len() >= MAX_GROUPS {
            return Err(());
        }
        let name = parse_group(body[cursor])?;
        cursor += 1;
        if cursor < body.len() && is_description(body[cursor]) {
            cursor += 1;
        }

        let mut limits = Vec::new();
        let mut saw_empty = false;
        while cursor < body.len() && body[cursor].starts_with("  ") {
            let line = body[cursor];
            cursor += 1;
            if line == "  - No active bucket limits" {
                if saw_empty || !limits.is_empty() {
                    return Err(());
                }
                saw_empty = true;
                continue;
            }
            if saw_empty || limits.len() >= MAX_LIMITS_PER_GROUP || total_limits >= MAX_TOTAL_LIMITS
            {
                return Err(());
            }
            limits.push(parse_limit(line)?);
            total_limits += 1;
        }
        if limits.is_empty() && !saw_empty {
            return Err(());
        }
        groups.push(AcpQuotaGroup { name, limits });
    }
    Ok(AcpUsageState::Ready { groups })
}

fn parse_group(line: &str) -> Result<String, ()> {
    let name = line
        .strip_prefix("- **")
        .and_then(|line| line.strip_suffix("**"))
        .ok_or(())?;
    bounded_name(name)
}

fn is_description(line: &str) -> bool {
    let trimmed = line.trim();
    trimmed.len() >= 2 && trimmed.starts_with('*') && trimmed.ends_with('*')
}

fn parse_limit(line: &str) -> Result<AcpQuotaLimit, ()> {
    let rest = line.strip_prefix("  - **").ok_or(())?;
    let (label, status) = rest.split_once(":** ").ok_or(())?;
    let label = bounded_name(label)?;
    let (status, next_reset_at) = match status.strip_suffix(')') {
        Some(prefix) => match prefix.rsplit_once(" (resets ") {
            Some((status, reset)) => (status, Some(parse_reset(reset)?)),
            None => (status, None),
        },
        None => (status, None),
    };
    let remaining = if let Some(value) = status.strip_suffix("% remaining") {
        let value = value.parse::<u8>().map_err(|_| ())?;
        if value > 100 {
            return Err(());
        }
        AcpQuotaRemaining::Percentage { value }
    } else if let Some(value) = status.strip_suffix(" units remaining") {
        AcpQuotaRemaining::Units {
            value: parse_units(value)?,
        }
    } else if status == "Available" {
        AcpQuotaRemaining::Unknown
    } else if status == "Disabled"
        || status
            .strip_prefix("Disabled: ")
            .is_some_and(|description| !description.is_empty())
    {
        AcpQuotaRemaining::Disabled
    } else {
        return Err(());
    };
    Ok(AcpQuotaLimit {
        label,
        remaining,
        next_reset_at,
    })
}

fn bounded_name(value: &str) -> Result<String, ()> {
    if value.is_empty() || value.len() > MAX_NAME_BYTES || value.contains(['\r', '\n']) {
        return Err(());
    }
    Ok(value.to_owned())
}

fn parse_units(value: &str) -> Result<u64, ()> {
    let mut parts = value.split(',');
    let first = parts.next().ok_or(())?;
    if first.is_empty() || first.len() > 3 || !first.bytes().all(|byte| byte.is_ascii_digit()) {
        return Err(());
    }
    let mut normalized = first.to_owned();
    for part in parts {
        if part.len() != 3 || !part.bytes().all(|byte| byte.is_ascii_digit()) {
            return Err(());
        }
        normalized.push_str(part);
    }
    normalized.parse().map_err(|_| ())
}

fn parse_reset(value: &str) -> Result<i64, ()> {
    let parts: Vec<&str> = value.split_whitespace().collect();
    let [month, day, year, time, "UTC"] = parts.as_slice() else {
        return Err(());
    };
    let month = match *month {
        "Jan" => 1,
        "Feb" => 2,
        "Mar" => 3,
        "Apr" => 4,
        "May" => 5,
        "Jun" => 6,
        "Jul" => 7,
        "Aug" => 8,
        "Sep" => 9,
        "Oct" => 10,
        "Nov" => 11,
        "Dec" => 12,
        _ => return Err(()),
    };
    let day = day
        .strip_suffix(',')
        .ok_or(())?
        .parse::<u32>()
        .map_err(|_| ())?;
    let year = year
        .strip_suffix(',')
        .ok_or(())?
        .parse::<i32>()
        .map_err(|_| ())?;
    let (hour, minute) = time.split_once(':').ok_or(())?;
    let hour = hour.parse::<u32>().map_err(|_| ())?;
    let minute = minute.parse::<u32>().map_err(|_| ())?;
    unix_utc(year, month, day, hour, minute)
}

fn unix_utc(year: i32, month: u32, day: u32, hour: u32, minute: u32) -> Result<i64, ()> {
    if !(1970..=9999).contains(&year) || !(1..=12).contains(&month) || hour > 23 || minute > 59 {
        return Err(());
    }
    let leap = year % 4 == 0 && (year % 100 != 0 || year % 400 == 0);
    let max_day = match month {
        2 if leap => 29,
        2 => 28,
        4 | 6 | 9 | 11 => 30,
        _ => 31,
    };
    if day == 0 || day > max_day {
        return Err(());
    }
    let adjusted_year = year - i32::from(month <= 2);
    let era = adjusted_year.div_euclid(400);
    let year_of_era = adjusted_year - era * 400;
    let shifted_month = i64::from(month) + if month > 2 { -3 } else { 9 };
    let day_of_year = (153 * shifted_month + 2) / 5 + i64::from(day) - 1;
    let day_of_era = i64::from(year_of_era) * 365 + i64::from(year_of_era / 4)
        - i64::from(year_of_era / 100)
        + day_of_year;
    let days = i64::from(era) * 146_097 + day_of_era - 719_468;
    Ok(days * 86_400 + i64::from(hour) * 3_600 + i64::from(minute) * 60)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_all_official_bucket_forms_and_ignores_session_usage() {
        let report = "\
### Session Usage
- **Session total:** 42 tokens

### Quota Limits
- **Gemini Models**
  *(Primary quota)*
  - **Weekly Limit Remaining:** 91% remaining (resets Oct 02, 2026, 08:22 UTC)
  - **Burst:** 1,234 units remaining
- **Other Models**
  - **Availability:** Available
  - **Legacy:** Disabled: retired
- **Empty**
  - No active bucket limits";
        assert_eq!(
            parse(report),
            Ok(AcpUsageState::Ready {
                groups: vec![
                    AcpQuotaGroup {
                        name: "Gemini Models".into(),
                        limits: vec![
                            AcpQuotaLimit {
                                label: "Weekly Limit Remaining".into(),
                                remaining: AcpQuotaRemaining::Percentage { value: 91 },
                                next_reset_at: Some(1_790_929_320),
                            },
                            AcpQuotaLimit {
                                label: "Burst".into(),
                                remaining: AcpQuotaRemaining::Units { value: 1_234 },
                                next_reset_at: None,
                            },
                        ],
                    },
                    AcpQuotaGroup {
                        name: "Other Models".into(),
                        limits: vec![
                            AcpQuotaLimit {
                                label: "Availability".into(),
                                remaining: AcpQuotaRemaining::Unknown,
                                next_reset_at: None,
                            },
                            AcpQuotaLimit {
                                label: "Legacy".into(),
                                remaining: AcpQuotaRemaining::Disabled,
                                next_reset_at: None,
                            },
                        ],
                    },
                    AcpQuotaGroup {
                        name: "Empty".into(),
                        limits: Vec::new(),
                    },
                ],
            })
        );
    }

    #[test]
    fn parses_special_states_without_exposing_raw_query_error() {
        assert_eq!(
            parse("### Quota Limits\n- Not applicable for current authentication method."),
            Ok(AcpUsageState::NotApplicable)
        );
        assert_eq!(
            parse("### Quota Limits\n- data not available yet"),
            Ok(AcpUsageState::Unavailable)
        );
        assert_eq!(
            parse("### Quota Limits\n- No quota limits reported."),
            Ok(AcpUsageState::Ready { groups: Vec::new() })
        );
        assert_eq!(
            parse("### Quota Limits\n- Unable to retrieve quota status (secret backend text)"),
            Ok(AcpUsageState::Failed {
                code: AcpUsageFailureCode::Query,
            })
        );
    }

    #[test]
    fn rejects_partial_or_malformed_quota_reports() {
        for report in [
            "### Session Usage\n- **Session total:** 42 tokens",
            "### Quota Limits\n- data not available yet\n- **Gemini Models**\n  - No active bucket limits",
            "### Quota Limits\n- **Gemini Models**\n  - **Weekly:** 101% remaining",
            "### Quota Limits\n- **Gemini Models**\n  - **Weekly:** 12,34 units remaining",
            "### Quota Limits\n- **Gemini Models**\n  - **Weekly:** Available (resets not-a-date)",
            "### Quota Limits\n- **Gemini Models**",
            "### Quota Limits\n- **Gemini Models**\n  - **Weekly:** surprise",
        ] {
            assert_eq!(parse(report), Err(()), "{report}");
        }
    }
}
