# Web-Watcher

A PowerShell-based website monitoring tool that automatically detects changes on websites and generates intelligent summaries using AI.

## Features

- **Automated Website Crawling**: Monitors multiple websites from a configurable list
- **Change Detection**: Compares current crawls with previous ones to identify modifications
- **AI-Powered Summaries**: Uses OpenAI GPT to generate Japanese summaries of detected changes
- **Visual Reports**: Creates HTML reports with colored diff visualization
- **Cross-Platform**: Works on Windows, Linux, and macOS with PowerShell Core

## Quick Start

1. **Clone and Setup**
   ```bash
   git clone https://github.com/hills-i/web-watcher.git
   cd web-watcher
   ```

2. **Configure API Key**
   Copy `config.example.json` to `config.json`:
   ```bash
   cp config.example.json config.json
   ```

3. **Add Websites to Monitor**
   Edit `website.txt` and add URLs (one per line):
   ```
   https://example.com
   https://another-site.com
   ```

4. **Run the Monitor**
   ```powershell
   .\Web-Watcher.ps1
   ```

## How It Works

1. **Crawling**: Downloads HTML content from each URL in `website.txt`
2. **Storage**: Saves content to `output/YYYY-MM-DD/hostname.html`
3. **Comparison**: Compares with previous crawl to detect changes
4. **AI Analysis**: Sends diffs to OpenAI for intelligent summarization in Japanese
5. **Reporting**: Generates `report-YYYY-MM-DD.html` with summaries and visual diffs

## Output Structure

```
web-watcher/
├── Web-Watcher.ps1          # Main script
├── website.txt              # URLs to monitor
├── config.example.json     # Example API configuration file
├── config.json             # API configuration (ignored via .gitignore)
├── output/
│   └── YYYY-MM-DD/         # Daily crawl results
│       ├── example.com.html
│       └── another-site.html
└── report-YYYY-MM-DD.html  # Generated reports
```

## Configuration

The `config.json` file must contain:
- `OpenAI_API_Key`: Your OpenAI API key for generating summaries

## Requirements

- PowerShell 5.1+ (Windows)
- Internet connection for crawling websites
- OpenAI API key for change summarization
- UTF-8 console support for proper Japanese text display

## Error Handling

The script includes robust error handling for:
- Network failures during website crawling
- OpenAI API errors and rate limits
- File system operations
- Missing configuration files

Failed operations are logged with warnings, and the script continues processing remaining sites.

## Politeness Features

- 3-second delay between website requests to avoid overwhelming servers
- Graceful error handling for unavailable sites
- UTF-8 encoding support for international content

## License

This project is provided as-is for educational and monitoring purposes.
