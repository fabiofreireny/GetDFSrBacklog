# GetDFSrBacklog
Outputs a table with the backlog of all DFS replications. Most scripts will not count beyond 100 files, but this script gives you the full result.

- Optionally outputs to an HTML file (which auto refreshes if copied to a virtual directory and is opened in a web browser)
- Multi-threaded for quick results
- Ability to filter on specific hosts
- Ability to omit connections without backlogs
