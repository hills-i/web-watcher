# Web-Watcher Main Script
# This script will perform website monitoring, diff detection, and reporting.
$PSDefaultParameterValues['*:Encoding'] = 'utf8'

# --- Initial Setup ---
Add-Type -AssemblyName System.Web
$ErrorActionPreference = "Stop" # Exit script on terminating errors

# Set console encoding for proper Japanese display
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# Define paths
$baseDir = $PWD.Path #Split-Path -Parent $MyInvocation.MyCommand.Definition
$websiteListPath = Join-Path $baseDir website.txt
$outputDir = Join-Path $baseDir output
$configPath = Join-Path $baseDir config.json

# --- Secure API Key Validation ---
if (-not (Test-Path $configPath)) {
    Write-Error Configuration file not found $configPath
    exit 1
}
$config = Get-Content -Path $configPath | ConvertFrom-Json
if (-not $config.OpenAI_API_Key -or [string]::IsNullOrWhiteSpace($config.OpenAI_API_Key) -or $config.OpenAI_API_Key -eq "YOUR_API_KEY_HERE") {
    Write-Error "OpenAI API key is not configured in config.json. Please add your key."
    exit 1
}
$apiKey = $config.OpenAI_API_Key
# Clear the config object from memory
$config = $null

# Create a directory for today's crawl results
$timestamp = Get-Date -Format yyyy-MM-dd
$todayDir = Join-Path $outputDir $timestamp
if (-not (Test-Path $todayDir)) {
    New-Item -ItemType Directory -Path $todayDir | Out-Null
}

# Find the previous crawl directory for comparison
$previousDir = Get-ChildItem -Path $outputDir -Directory | Sort-Object Name | Select-Object -Last 1
if ($previousDir -and (Get-ChildItem -Path $outputDir -Directory).Count -gt 1) {
    $previousDir = (Get-ChildItem -Path $outputDir -Directory | Sort-Object Name)[-2].FullName
    Write-Host Previous crawl directory found $previousDir
} else {
    $previousDir = $null
    Write-Host No previous crawl directory found. Skipping diff check.
}


# --- Main Processing Loop ---
# Read URLs from the file
$urls = Get-Content $websiteListPath

$changedSites = New-Object 'System.Collections.Generic.List[object]'

foreach ($url in $urls) {
    try {
        Write-Host Processing $url

        # Generate a clean filename from the URL's host
$uri = [System.Uri]$url
$hostname = $uri.Host
$outputFilePath = Join-Path $todayDir "$hostname.html"

# Fetch the website content
$response = Invoke-WebRequest -Uri $url

# Filter sensitive data from content before saving
$filteredContent = $response.Content
$filteredContent = $filteredContent -replace 'password\s*[:=]\s*["''][^"''>]*["'']', 'password="***"'
$filteredContent = $filteredContent -replace 'api[_-]?key\s*[:=]\s*["''][^"''>]*["'']', 'api_key="***"'
$filteredContent = $filteredContent -replace 'token\s*[:=]\s*["''][^"''>]*["'']', 'token="***"'

# Save the filtered content to the file
$filteredContent | Out-File -FilePath $outputFilePath -Encoding utf8

        Write-Host  - Saved to $outputFilePath

        # --- Diff Check ---
        if ($previousDir) {
            $previousFilePath = Join-Path $previousDir "$hostname.html"
            Write-Host  - Comparing with "$hostname.html"
            if (Test-Path $previousFilePath) {
                Write-Host  - Comparing with $previousFilePath
                $diff = Compare-Object -ReferenceObject (Get-Content $previousFilePath) -DifferenceObject (Get-Content $outputFilePath)

                if ($diff -and $diff.Count -gt 0)  {
                    Write-Host     - Differences found!
                    $change = [PSCustomObject]@{
                        Url = $url
                        Diff = $diff
                        NewContent = $filteredContent
                    }
                    $changedSites.Add($change)
                }
            } else {
                Write-Host  - Previous file not found, skipping comparison.
            }
        }

    } catch {
        Write-Warning "Failed to process '$url'. Error $($_.Exception.Message)"
    } finally {
        # Politeness delay to avoid overwhelming servers
        Start-Sleep -Seconds 3
    }
}

    # --- OpenAI Summarization ---
    if ($changedSites.Count -gt 0) {
        Write-Host "`n--- Found $($changedSites.Count) sites with changes. Summarizing with OpenAI... ---"

        foreach ($site in $changedSites) {
            try {
                Write-Host "Summarizing changes for $($site.Url)"

                # Format the diff for the prompt
                $formattedDiff = $site.Diff | ForEach-Object {
                    $indicator = switch ($_.SideIndicator) {
                        '<=' { '-' }
                        '=>' { '+' }
                        default { '' }
                    }
                    "$indicator$($_.InputObject)"
                } | Out-String

                # Construct the prompt
                $prompt = @"
Based on the following diff and the new page content, please provide a concise summary of the changes.
Focus on user-visible changes like new features, updated text, or removed sections. Ignore minor code or style changes.
The summary should be in Japanese.

## Diff (`-` indicates removed, `+` indicates added)
```diff
$formattedDiff
```

## New Page Content
```html
$($site.NewContent)
```

## Summary of Changes (in Japanese)
"@

                # Build the API request body
                $headers = @{
                    Authorization = "Bearer $apiKey"
                    "Content-Type"  = "application/json; charset=utf-8"
                }
                $body = @{
                    model = "gpt-5-nano"
                    messages = @(
                        @{
                            role = "system"
                            content = "You are a helpful assistant who summarizes website changes for a user."
                        },
                        @{
                            role = "user"
                            content = $prompt
                        }
                    )
                    temperature = 0.5
                } | ConvertTo-Json -Depth 5

                # Call the API with UTF-8 encoding
                $webRequest = [System.Net.WebRequest]::Create("https://api.openai.com/v1/chat/completions")
                $webRequest.Method = "POST"
                $webRequest.ContentType = "application/json; charset=utf-8"
                $webRequest.Headers.Add("Authorization", "Bearer $apiKey")
                
                $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($body)
                $webRequest.ContentLength = $bodyBytes.Length
                
                $requestStream = $webRequest.GetRequestStream()
                $requestStream.Write($bodyBytes, 0, $bodyBytes.Length)
                $requestStream.Close()
                
                $webResponse = $webRequest.GetResponse()
                $responseStream = $webResponse.GetResponseStream()
                $reader = [System.IO.StreamReader]::new($responseStream, [System.Text.Encoding]::UTF8)
                $responseText = $reader.ReadToEnd()
                $reader.Close()
                $webResponse.Close()
                
                $response = $responseText | ConvertFrom-Json
                
                # Validate API response structure
                if (-not $response -or -not $response.choices -or $response.choices.Count -eq 0 -or -not $response.choices[0].message) {
                    throw "Invalid API response structure"
                }
                
                $summary = $response.choices[0].message.content.Trim()
                
                # Ensure UTF-8 string handling
                $summaryBytes = [System.Text.Encoding]::UTF8.GetBytes($summary)
                $summary = [System.Text.Encoding]::UTF8.GetString($summaryBytes)

                # Add the summary to the site object
                $site | Add-Member -MemberType NoteProperty -Name Summary -Value $summary
                Write-Host " - Summary received.  $summary"

            } catch {
                Write-Warning "Failed to get summary for '$($site.Url)'. Error $($_.Exception.Message)"
                # Add a placeholder summary on failure
                $site | Add-Member -MemberType NoteProperty -Name Summary -Value "Failed to generate summary."
            }
        }
        
        # Clear API key from memory after all API calls
        $apiKey = $null

        # --- HTML Report Generation ---
        Write-Host "`n--- Generating HTML report... ---"
        $reportPath = Join-Path $baseDir "report-$timestamp.html"

        # Simple CSS for the report
        $css = @"
<style>
    body { font-family: sans-serif; line-height: 1.6; }
    h1, h2 { border-bottom: 2px solid #eee; padding-bottom: 5px; }
    .site-section { border: 1px solid #ccc; padding: 10px; margin-bottom: 20px; border-radius: 5px; }
    .summary { background-color: #f8f9fa; border-left: 5px solid #007bff; padding: 10px; margin-top: 10px; }
    pre { background-color: #f1f1f1; padding: 10px; border-radius: 3px; white-space: pre-wrap; word-wrap: break-word; }
    .diff-add { color: #28a745; }
    .diff-del { color: #dc3545; text-decoration: line-through; }
</style>
"@

        # Start building the HTML body
        $htmlBody = "<h1>Web-Watcher Report - $timestamp</h1>"

        foreach ($site in $changedSites) {
            # Format the diff with HTML spans for color
            $htmlDiff = ($site.Diff | ForEach-Object {
                $line = [System.Web.HttpUtility]::HtmlEncode($_.InputObject)
                switch ($_.SideIndicator) {
                    '<=' { "<span class='diff-del'>-$line</span>" }
                    '=>' { "<span class='diff-add'>+$line</span>" }
                    default { $line }
                }
            }) -join "`n"

            $htmlBody += @"
<div class='site-section'>
    <h2><a href='$($site.Url)' target='_blank'>$($site.Url)</a></h2>
    <h3>Summary of Changes</h3>
    <div class='summary'>
        <p>$($site.Summary -replace "`n", "<br>")</p>
    </div>
    <h3>Detail</h3>
    <pre>$htmlDiff</pre>
</div>
"@
        }

        # Combine into a full HTML document
        $htmlContent = @"
<!DOCTYPE html>
<html lang='en'>
<head>
    <meta charset='UTF-8' />
    <title>Web-Watcher Report</title>
    $css
</head>
<body>
    $htmlBody
</body>
</html>
"@

        # Save the report and open it with explicit UTF-8 BOM
        [System.IO.File]::WriteAllText($reportPath, $htmlContent, [System.Text.Encoding]::UTF8)
        Write-Host " - Report saved to $reportPath"
        if ($IsWindows) {
            Invoke-Item $reportPath
        } else {
            Write-Host "To view the report, open this file in your browser: $reportPath"
        }
    }

    Write-Host "Script finished."
