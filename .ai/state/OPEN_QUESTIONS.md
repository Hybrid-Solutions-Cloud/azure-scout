# Open questions

<!-- Unresolved questions or deferred decisions for the next session or tool to pick up. -->

See the customer reliability investigation questions below.

## Customer reliability investigation — 2026-09-18

- Locate original August 14 customer log/raw ReportCache and latest five-tenant run-summary/child logs; supplied folder contains only corrected report/JSON/backup artifacts.
- Obtain Graph probe/Gap and customer-side export scripts to establish bug ownership and validate import schema.
- Completed: browser verification became available through scratch Playwright/headless Edge. Reviewed the generated report, details, diagrams, mobile and print layouts; fixed mobile sidebar and print formatting. CUA remains unavailable but is no longer a verification blocker.

Confirmed code fixes and acceptance gates are in CUSTOMER_RELIABILITY_ISSUES.md and CUSTOMER_RELIABILITY_PLAN.md. No response with missing locations has arrived yet. The goal is blocked on original evidence for full incident reconciliation, not on approval to inspect it.
