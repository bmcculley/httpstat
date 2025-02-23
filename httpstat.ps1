param (
    [string]$Help,
    [string]$H,
    [string]$Version,
    [string]$D,
    [string]$Url,
    [Parameter(ValueFromRemainingArguments=$true)]
    [string[]]$RemainingArgs
)

# Function to escape inner quotes and surround with double quotes
function EscapeAndQuote {
    param ($arg)
    if ($arg -match '^\{.*\}$') {
        # Escape inner quotes and surround with double quotes
        return '"' + $arg.Replace('"', '\"') + '"'
    }
    return $arg
}

$scriptArgs = @()

function print_help {
    $helpText = @"
Usage: httpstat URL [CURL_OPTIONS]
       httpstat --help
       httpstat --version
Arguments:
  URL     url to request, could be with or without `http(s)://` prefix
Options:
  CURL_OPTIONS  any curl supported options, except for -w -D -o -S -s,
                which are already used internally.
  --help     show this screen.
  --version     show version.
Environments:
  HTTPSTAT_SHOW_HEAD    By default httpstat will write response headers
                        in a tempfile and print them but you can prevent
                        printing out by setting this variable to false.
  HTTPSTAT_SHOW_BODY    By default httpstat will write response body
                        in a tempfile, but you can let it print out by setting
                        this variable to true.
  HTTPSTAT_SHOW_SPEED   set to true to show download and upload speed.
"@
    Write-Output $helpText
}

# Test if curl.exe is available before continuing
try {
    Get-Command curl.exe -ErrorAction Stop | Out-Null
} catch {
    Write-Host "Error: curl.exe needs to be installed." -ForegroundColor Red
    exit 1
}

# Process the parameters
if ($Help -match "--help") {
    print_help
    exit
}
if ($Version -match "--version") {
    Write-Output "httpstat 0.0.1"
    exit
}

if ($WriteOut) { $scriptArgs += "--write-out $WriteOut" }
if ($DumpHeader) { $scriptArgs += "--dump-header $DumpHeader" }
if ($Output) { $scriptArgs += "--output $Output" }
if ($Silent) { $scriptArgs += "--silent" }
if ($H) { $scriptArgs += "-H $(EscapeAndQuote $H)" }
if ($D) { $scriptArgs += "-d $(EscapeAndQuote $D)" }
if ($Url) { $url = $Url }

# Process remaining arguments
foreach ($arg in $RemainingArgs) {
    # Check if the argument looks like a URL
    if ($arg -match '^http.*') {
        $url = $arg
    } else {
        $scriptArgs += $arg
    }
}

# janky...but check if it's set to help
if ($help -match '^http.*') {
    $url = $help
}


if (-not $url) {
    Write-Error -Message "Too few arguments"
    print_help
    exit 1
}

$curl_format = '{
"time_namelookup": %{time_namelookup},
"time_connect": %{time_connect},
"time_appconnect": %{time_appconnect},
"time_pretransfer": %{time_pretransfer},
"time_redirect": %{time_redirect},
"time_starttransfer": %{time_starttransfer},
"time_total": %{time_total},
"speed_download": %{speed_download},
"speed_upload": %{speed_upload}
}'

$head = [System.IO.Path]::GetTempFileName()
$body = [System.IO.Path]::GetTempFileName()

$data = & curl.exe -w $curl_format -D $head -o $body -s -S $scriptArgs $url 2>&1

function get($key) {
    $value = $data | Select-String -Pattern $key | ForEach-Object { $_.Line.Split(' ')[1].TrimEnd(',') }
    if ($value -match '^\d+(\.\d+)?$') {
        return [math]::Round([decimal]$value * 1000, 0)
    }
    return $value
}

function calc($expr) {
    try {
        return Invoke-Expression $expr
    } catch {
        return $null
    }
}

$time_namelookup = get "time_namelookup"
$time_connect = get "time_connect"
$time_appconnect = get "time_appconnect"
$time_pretransfer = get "time_pretransfer"
$time_redirect = get "time_redirect"
$time_starttransfer = get "time_starttransfer"
$time_total = get "time_total"
$speed_download = get "speed_download"
$speed_upload = get "speed_upload"

$range_dns = $time_namelookup
$range_connection = calc "$time_connect - $time_namelookup"
$range_ssl = calc "$time_pretransfer - $time_connect"
$range_server = calc "$time_starttransfer - $time_pretransfer"
$range_transfer = calc "$time_total - $time_starttransfer"

function fmta($val) {
    return "{0,5:N0}ms" -f $val
}

function fmtb($val) {
    return "{0,4:N0}ms" -f $val
}

$a000 = "$(fmta $range_dns)"
$a001 = "$(fmta $range_connection)"
$a002 = "$(fmta $range_ssl)"
$a003 = "$(fmta $range_server)"
$a004 = "$(fmta $range_transfer)"

$b000 = "$(fmtb $time_namelookup)"
$b001 = "$(fmtb $time_connect)"
$b002 = "$(fmtb $time_pretransfer)"
$b003 = "$(fmtb $time_starttransfer)"
$b004 = "$(fmtb $time_total)"

function https_template {
    # Template
    Write-Host "`n  DNS Lookup   TCP Connection   SSL Handshake   Server Processing   Content Transfer"
    Write-Host -NoNewline "[" -ForegroundColor White
    Write-Host -NoNewline "   $a000" -ForegroundColor Cyan
    Write-Host -NoNewline " |     "
    Write-Host -NoNewline "$a001" -ForegroundColor Cyan
    Write-Host -NoNewline "    |    "
    Write-Host -NoNewline "$a002" -ForegroundColor Cyan
    Write-Host -NoNewline "    |      "
    Write-Host -NoNewline "$a003" -ForegroundColor Cyan
    Write-Host -NoNewline "      |      "
    Write-Host -NoNewline "$a004" -ForegroundColor Cyan
    Write-Host "     ]"

    Write-Host "            |                |               |                   |                  |"
    Write-Host -NoNewline "   namelookup:"
    Write-Host -NoNewline "$b000" -ForegroundColor Cyan
    Write-Host "         |               |                   |                  |"
    Write-Host -NoNewline "                        connect:"
    Write-Host -NoNewline "$b001" -ForegroundColor Cyan
    Write-Host "       |                   |                  |"
    Write-Host -NoNewline "                                    pretransfer:"
    Write-Host -NoNewline "$b002" -ForegroundColor Cyan
    Write-Host "           |                  |"
    Write-Host -NoNewline "                                                       starttransfer:"
    Write-Host -NoNewline "$b003" -ForegroundColor Cyan
    Write-Host "         |"
    Write-Host -NoNewline "                                                                                  total:"
    Write-Host "$b004" -ForegroundColor Cyan
}

function http_template {
    # Template
    Write-Host "`n  DNS Lookup   TCP Connection   Server Processing   Content Transfer"
    Write-Host -NoNewline "[" -ForegroundColor White;
    Write-Host -NoNewline "   $a000" -ForegroundColor Cyan;
    Write-Host -NoNewline " |     "
    Write-Host -NoNewline "$a001" -ForegroundColor Cyan;
    Write-Host -NoNewline "    |    "
    Write-Host -NoNewline "$a003" -ForegroundColor Cyan;
    Write-Host -NoNewline "        |     "
    Write-Host -NoNewline "$a004" -ForegroundColor Cyan
    Write-Host "      ]"

    Write-Host "            |                |                   |                  |"
    Write-Host -NoNewline "   namelookup:"
    Write-Host -NoNewline "$b000" -ForegroundColor Cyan
    Write-Host "         |                   |                  |"
    Write-Host -NoNewline "                        connect:"
    Write-Host -NoNewline "$b001" -ForegroundColor Cyan
    Write-Host "           |                  |"
    Write-Host -NoNewline "                                       starttransfer:"
    Write-Host -NoNewline "$b003" -ForegroundColor Cyan
    Write-Host "         |"
    Write-Host -NoNewline "                                                                  total:"
    Write-Host "$b004" -ForegroundColor Cyan
}

if (-not $env:HTTPSTAT_SHOW_HEAD -or $env:HTTPSTAT_SHOW_HEAD -eq "true") {
    $headers = Get-Content $head;

    # Loop through each line and colorize the output
    foreach ($line in $headers) {
        if ($line -match "^HTTP/.*") {
            # Split the line into key and value
            $parts = $line -split "/", 2
            $key = $parts[0].Trim()
            $value = $parts[1].Trim()
            # Colorize the HTTP line
            Write-Host -NoNewline "$key/" -ForegroundColor Yellow
            Write-Host $value -ForegroundColor Cyan
        } else {
            # Split the line into key and value
            $parts = $line -split ":", 2
            if ($parts.Length -eq 2) {
                $key = $parts[0].Trim()
                $value = $parts[1].Trim()

                # Colorize the key and value
                Write-Host -NoNewline "$key`: "
                Write-Host $value -ForegroundColor Cyan
            } else {
                Write-Host $line
            }
        }
    }
} else {
    Write-Host -NoNewline "Headers " -ForegroundColor Yellow 
    Write-Host "stored in: $head"
}

# output, need to print escape sequences raw (disable those checks for shellcheck)
if ($env:HTTPSTAT_SHOW_BODY -eq "true") {
    Get-Content $body
    Write-Output ''
} else {
    Write-Host -NoNewline "Body " -ForegroundColor Yellow 
    Write-Host "stored in: $body"
}

if ($url -match "^https://") {
    https_template
} else {
    http_template
}

if ($env:HTTPSTAT_SHOW_SPEED -eq "true") {
    Write-Output "speed_download $(calc "$speed_download / 1024") KiB, speed_upload $(calc "$speed_upload / 1024") KiB"
}
