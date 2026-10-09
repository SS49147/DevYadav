# Exercise 6 results

Tested on 9 October 2026 with Docker Desktop 4.94.0, a dedicated Docker 29.8.2 daemon, Jenkins 2.580.1, Prometheus 3.5.0 and Grafana 12.1.1.

| Scenario | Jenkins build | Result | Monitoring checks | Pending snapshot | Observed mean |
| --- | --- | --- | --- | --- | --- |
| Normal | 2 | SUCCESS | 16 passed | 13 | 30.30 seconds |
| High pending | 3 | SUCCESS | 17 passed | 88 | 31.28 seconds |
| High pending and slow | 4 | SUCCESS | 19 passed | 75 | 40.03 seconds |

The snapshots are individual readings, not fixed simulator values. Four Python tests passed during each build, and `promtool` accepted the configuration and both rules. The original first normal build also succeeded; build 2 verified the cached rerun. The checked-in normal console/report are from build 2.

Both scrape targets were up. Grafana's data source health check passed, and all four required expressions returned data through Grafana's Prometheus proxy. In the high-pending scenario, `HighPendingDeliveries` reached firing state with severity warning. The controlled slow scenario required both `HighPendingDeliveries` and `HighAverageDeliveryTime` to be firing, and both were returned by the dashboard's alert query.

The normal observed mean was already slightly above the source's 30-second threshold at verification time. These thresholds can fire during the normal random workload; normal does not mean all alerts must be inactive. The high-pending screenshot also shows both firing alerts because its random observed mean was above 30 seconds.

Jenkins replaces the three monitoring containers between scenarios, so open browser requests can fail briefly during that replacement. A fresh dashboard load after the last restart showed the live panels and both alerts without browser console errors. These are Prometheus rule states displayed in Grafana, not externally delivered notifications.

## Evidence

- [Normal Jenkins output](evidence/jenkins-normal.txt) and [verification](evidence/verification-normal.json)
- [High-pending Jenkins output](evidence/jenkins-high_pending.txt) and [verification](evidence/verification-high_pending.json)
- [Controlled slow Jenkins output](evidence/jenkins-high_pending_slow.txt) and [verification](evidence/verification-high_pending_slow.json)
- [Normal dashboard](evidence/dashboard-normal.png)
- [High-pending dashboard](evidence/dashboard-high-pending.png)
- [Dashboard with both alerts](evidence/dashboard-both-alerts.png)
- [Prometheus alert details](evidence/prometheus-alerts.png)

The lab remains available locally. No pre-existing containers were stopped or removed.
