# Zeus Academia - Startup Script
# This script starts the backend API, Student Portal, and Faculty Dashboard

param(
    [switch]$WaitForExit,
    [switch]$SkipHealthCheck,
    [int]$HealthCheckTimeout = 30,
    [switch]$StudentOnly,
    [switch]$FacultyOnly,
    [switch]$AdminOnly
)

# Ensure we're running from the correct directory
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = $scriptDir
Set-Location $projectRoot

Write-Host "🏛️ ZEUS ACADEMIA - STARTUP SCRIPT" -ForegroundColor Yellow
Write-Host "=================================" -ForegroundColor Yellow
Write-Host "📂 Working Directory: $projectRoot" -ForegroundColor Gray
Write-Host ""

# Configuration
$apiPath = "C:\git\zeus\zeus.academia.2\src\Zeus.Academia.Api"
$frontendPath = "C:\git\zeus\zeus.academia.2\src\Zeus.Academia.StudentPortal"
$facultyDashboardPath = "C:\git\zeus\zeus.academia.2\src\Zeus.Academia.FacultyDashboard"
$adminInterfacePath = "C:\git\zeus\zeus.academia.2\src\Zeus.Academia.AdminInterface"
$apiPort = 5000
$frontendPort = 5173
$facultyDashboardPort = 5174
$adminInterfacePort = 5175
$apiUrl = "http://localhost:$apiPort"
$frontendUrl = "http://localhost:$frontendPort"
$facultyDashboardUrl = "http://localhost:$facultyDashboardPort"
$adminInterfaceUrl = "http://localhost:$adminInterfacePort"

# Function to check if a port is in use
function Test-PortInUse {
    param([int]$Port)
    $connections = netstat -ano | Select-String ":$Port\s"
    return $connections.Count -gt 0
}

# Function to wait for service to be ready
function Wait-ForService {
    param(
        [string]$Url,
        [string]$ServiceName,
        [int]$TimeoutSeconds = 30
    )

    Write-Host "⏳ Waiting for $ServiceName to start..." -ForegroundColor Yellow
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    do {
        Start-Sleep -Seconds 2
        try {
            Invoke-RestMethod -Uri $Url -TimeoutSec 5 -ErrorAction Stop | Out-Null
            Write-Host "✅ $ServiceName is ready!" -ForegroundColor Green
            return $true
        }
        catch {
            Write-Host "." -NoNewline -ForegroundColor Gray
        }
    } while ($stopwatch.Elapsed.TotalSeconds -lt $TimeoutSeconds)

    Write-Host ""
    Write-Host "❌ $ServiceName failed to start within $TimeoutSeconds seconds" -ForegroundColor Red
    return $false
}

# Function to kill processes using a specific port
function Stop-ProcessOnPort {
    param([int]$Port)

    $connections = netstat -ano | Select-String ":$Port\s"
    if ($connections) {
        Write-Host "⚠️ Port $Port is in use. Stopping existing processes..." -ForegroundColor Yellow
        $pids = $connections | ForEach-Object {
            ($_ -split '\s+')[-1]
        } | Sort-Object -Unique

        foreach ($processId in $pids) {
            try {
                Stop-Process -Id $processId -Force -ErrorAction SilentlyContinue
                Write-Host "  Stopped process $processId" -ForegroundColor Gray
            }
            catch {
                Write-Host "  Could not stop process $processId" -ForegroundColor Yellow
            }
        }
        Start-Sleep -Seconds 2
    }
}

# Pre-flight checks
Write-Host "🔍 PRE-FLIGHT CHECKS" -ForegroundColor Cyan
Write-Host "=====================" -ForegroundColor Cyan

# Check if directories exist
if (-not (Test-Path $apiPath)) {
    Write-Host "❌ API directory not found: $apiPath" -ForegroundColor Red
    exit 1
}

if (-not $FacultyOnly -and -not (Test-Path $frontendPath)) {
    Write-Host "❌ Student Portal directory not found: $frontendPath" -ForegroundColor Red
    exit 1
}

if (-not $StudentOnly -and -not (Test-Path $facultyDashboardPath)) {
    Write-Host "❌ Faculty Dashboard directory not found: $facultyDashboardPath" -ForegroundColor Red
    exit 1
}

if (($AdminOnly -or (-not $StudentOnly -and -not $FacultyOnly)) -and -not (Test-Path $adminInterfacePath)) {
    Write-Host "❌ Admin Interface directory not found at: $adminInterfacePath" -ForegroundColor Red
    exit 1
}

Write-Host "✅ API directory found: $apiPath" -ForegroundColor Green
if (-not $FacultyOnly -and -not $AdminOnly) { Write-Host "✅ Student Portal directory found: $frontendPath" -ForegroundColor Green }
if (-not $StudentOnly -and -not $AdminOnly) { Write-Host "✅ Faculty Dashboard directory found: $facultyDashboardPath" -ForegroundColor Green }
if ($AdminOnly -or (-not $StudentOnly -and -not $FacultyOnly)) { Write-Host "✅ Admin Interface directory found: $adminInterfacePath" -ForegroundColor Green }

# Check required tools
try {
    $dotnetVersion = dotnet --version
    Write-Host "✅ .NET SDK: $dotnetVersion" -ForegroundColor Green
}
catch {
    Write-Host "❌ .NET SDK not found. Please install .NET 9 SDK" -ForegroundColor Red
    exit 1
}

try {
    $nodeVersion = node --version
    Write-Host "✅ Node.js: $nodeVersion" -ForegroundColor Green
}
catch {
    Write-Host "❌ Node.js not found. Please install Node.js 18+" -ForegroundColor Red
    exit 1
}

try {
    $npmVersion = npm --version
    Write-Host "✅ npm: $npmVersion" -ForegroundColor Green
}
catch {
    Write-Host "❌ npm not found" -ForegroundColor Red
    exit 1
}

Write-Host ""

# Clear ports if in use
Write-Host "🧹 PORT CLEANUP" -ForegroundColor Cyan
Write-Host "===============" -ForegroundColor Cyan

Stop-ProcessOnPort -Port $apiPort
if (-not $FacultyOnly -and -not $AdminOnly) { Stop-ProcessOnPort -Port $frontendPort }
if (-not $StudentOnly -and -not $AdminOnly) { Stop-ProcessOnPort -Port $facultyDashboardPort }
if ($AdminOnly -or (-not $StudentOnly -and -not $FacultyOnly)) { Stop-ProcessOnPort -Port $adminInterfacePort }

Write-Host "✅ Ports cleared" -ForegroundColor Green
Write-Host ""

# Start Backend API
Write-Host "🚀 STARTING BACKEND API" -ForegroundColor Cyan
Write-Host "========================" -ForegroundColor Cyan

try {
    Write-Host "📂 Navigating to API directory..." -ForegroundColor Gray
    Push-Location $apiPath

    Write-Host "🔨 Building API..." -ForegroundColor Yellow
    dotnet build --verbosity quiet | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "❌ API build failed" -ForegroundColor Red
        Pop-Location
        exit 1
    }
    Write-Host "✅ API build successful" -ForegroundColor Green

    Write-Host "▶️ Starting API server..." -ForegroundColor Yellow

    # Start API in background
    $apiJob = Start-Job -ScriptBlock {
        param($path)
        Set-Location $path
        dotnet run --urls "http://localhost:5000"
    } -ArgumentList $apiPath

    Pop-Location

    Write-Host "🔄 API Job ID: $($apiJob.Id)" -ForegroundColor Gray

    if (-not $SkipHealthCheck) {
        $apiReady = Wait-ForService -Url "$apiUrl/health" -ServiceName "Backend API" -TimeoutSeconds $HealthCheckTimeout
        if (-not $apiReady) {
            Write-Host "❌ Failed to start Backend API" -ForegroundColor Red
            Stop-Job $apiJob -ErrorAction SilentlyContinue
            Remove-Job $apiJob -ErrorAction SilentlyContinue
            exit 1
        }
    }
}
catch {
    Write-Host "❌ Error starting Backend API: $($_.Exception.Message)" -ForegroundColor Red
    Pop-Location
    exit 1
}

Write-Host ""

# Start Student Portal
if (-not $FacultyOnly -and -not $AdminOnly) {
    Write-Host "� STARTING STUDENT PORTAL" -ForegroundColor Cyan
    Write-Host "==========================" -ForegroundColor Cyan

    try {
        Write-Host "📂 Navigating to student portal directory..." -ForegroundColor Gray
        Push-Location $frontendPath

        # Check if node_modules exists
        if (-not (Test-Path "node_modules")) {
            Write-Host "📦 Installing dependencies..." -ForegroundColor Yellow
            npm install --silent
            if ($LASTEXITCODE -ne 0) {
                Write-Host "❌ Student Portal dependency installation failed" -ForegroundColor Red
                Pop-Location
                exit 1
            }
            Write-Host "✅ Dependencies installed" -ForegroundColor Green
        }
        else {
            Write-Host "✅ Dependencies already installed" -ForegroundColor Green
        }

        Write-Host "▶️ Starting student portal server..." -ForegroundColor Yellow

        # Start Student Portal in background
        $frontendJob = Start-Job -ScriptBlock {
            param($path)
            Set-Location $path
            npm run dev
        } -ArgumentList $frontendPath

        Pop-Location

        Write-Host "🔄 Student Portal Job ID: $($frontendJob.Id)" -ForegroundColor Gray

        if (-not $SkipHealthCheck) {
            # Wait a bit for Vite to start
            Start-Sleep -Seconds 5
            Write-Host "✅ Student Portal starting (Vite typically takes 2-5 seconds)" -ForegroundColor Green
        }
    }
    catch {
        Write-Host "❌ Error starting Student Portal: $($_.Exception.Message)" -ForegroundColor Red
        Pop-Location
        exit 1
    }

    Write-Host ""
}

# Start Faculty Dashboard
if (-not $StudentOnly -and -not $AdminOnly) {
    Write-Host "👨‍🏫 STARTING FACULTY DASHBOARD" -ForegroundColor Cyan
    Write-Host "===============================" -ForegroundColor Cyan

    try {
        Write-Host "📂 Navigating to faculty dashboard directory..." -ForegroundColor Gray
        Push-Location $facultyDashboardPath

        # Check if node_modules exists
        if (-not (Test-Path "node_modules")) {
            Write-Host "📦 Installing dependencies..." -ForegroundColor Yellow
            npm install --silent
            if ($LASTEXITCODE -ne 0) {
                Write-Host "❌ Faculty Dashboard dependency installation failed" -ForegroundColor Red
                Pop-Location
                exit 1
            }
            Write-Host "✅ Dependencies installed" -ForegroundColor Green
        }
        else {
            Write-Host "✅ Dependencies already installed" -ForegroundColor Green
        }

        Write-Host "▶️ Starting faculty dashboard server..." -ForegroundColor Yellow

        # Start Faculty Dashboard in background
        $facultyJob = Start-Job -ScriptBlock {
            param($path)
            Set-Location $path
            npm run dev
        } -ArgumentList $facultyDashboardPath

        Pop-Location

        Write-Host "🔄 Faculty Dashboard Job ID: $($facultyJob.Id)" -ForegroundColor Gray

        if (-not $SkipHealthCheck) {
            # Wait a bit for Vite to start
            Start-Sleep -Seconds 5
            Write-Host "✅ Faculty Dashboard starting (Vite typically takes 2-5 seconds)" -ForegroundColor Green
        }
    }
    catch {
        Write-Host "❌ Error starting Faculty Dashboard: $($_.Exception.Message)" -ForegroundColor Red
        Pop-Location
        exit 1
    }

    Write-Host ""
}

# Start Admin Interface
if ($AdminOnly -or (-not $StudentOnly -and -not $FacultyOnly)) {
    Write-Host "🔐 STARTING ADMIN INTERFACE" -ForegroundColor Cyan
    Write-Host "============================" -ForegroundColor Cyan

    try {
        Write-Host "📂 Navigating to admin interface directory..." -ForegroundColor Gray
        Push-Location $adminInterfacePath

        # Check if node_modules exists
        if (-not (Test-Path "node_modules")) {
            Write-Host "📦 Installing dependencies..." -ForegroundColor Yellow
            npm install --silent
            if ($LASTEXITCODE -ne 0) {
                Write-Host "❌ Admin Interface dependency installation failed" -ForegroundColor Red
                Pop-Location
                exit 1
            }
            Write-Host "✅ Dependencies installed" -ForegroundColor Green
        }
        else {
            Write-Host "✅ Dependencies already installed" -ForegroundColor Green
        }

        Write-Host "▶️ Starting admin interface server..." -ForegroundColor Yellow

        # Start Admin Interface in background
        $adminJob = Start-Job -ScriptBlock {
            param($path)
            Set-Location $path
            npm run dev
        } -ArgumentList $adminInterfacePath

        Pop-Location

        Write-Host "🔄 Admin Interface Job ID: $($adminJob.Id)" -ForegroundColor Gray

        if (-not $SkipHealthCheck) {
            # Wait a bit for Vite to start
            Start-Sleep -Seconds 5
            Write-Host "✅ Admin Interface starting (Vite typically takes 2-5 seconds)" -ForegroundColor Green
        }
    }
    catch {
        Write-Host "❌ Error starting Admin Interface: $($_.Exception.Message)" -ForegroundColor Red
        Pop-Location
        exit 1
    }

    Write-Host ""
}

Write-Host ""

# Report endpoints and status
Write-Host "📊 SERVICE STATUS & ENDPOINTS" -ForegroundColor Green
Write-Host "=============================" -ForegroundColor Green

# Test API endpoints
try {
    $health = Invoke-RestMethod -Uri "$apiUrl/health" -TimeoutSec 5
    Write-Host "✅ Backend API: RUNNING" -ForegroundColor Green
    Write-Host "   🌐 Health: $apiUrl/health" -ForegroundColor Cyan
    Write-Host "   📊 Status: $($health.status)" -ForegroundColor Cyan
    Write-Host "   🏷️ Service: $($health.service)" -ForegroundColor Cyan
    Write-Host "   📅 Version: $($health.version)" -ForegroundColor Cyan

    # Test key endpoints
    Write-Host "   🔗 Key Endpoints:" -ForegroundColor Cyan
    Write-Host "      • API Info: $apiUrl/" -ForegroundColor White
    Write-Host "      • Student Profile: $apiUrl/api/student/profile" -ForegroundColor White
    Write-Host "      • Course Catalog: $apiUrl/api/courses/paginated" -ForegroundColor White
    Write-Host "      • Enrollments: $apiUrl/api/student/enrollments" -ForegroundColor White
    Write-Host "      • Authentication: $apiUrl/api/auth/login" -ForegroundColor White
}
catch {
    Write-Host "⚠️ Backend API: STARTING (may take a few more seconds)" -ForegroundColor Yellow
    Write-Host "   🌐 Expected URL: $apiUrl" -ForegroundColor Cyan
}

Write-Host ""

# Check Student Portal status
if (-not $FacultyOnly -and -not $AdminOnly) {
    if (Test-PortInUse -Port $frontendPort) {
        Write-Host "✅ Student Portal: RUNNING" -ForegroundColor Green
        Write-Host "   🌐 Application: $frontendUrl/" -ForegroundColor Cyan
        Write-Host "   🔑 Demo Login:" -ForegroundColor Cyan
        Write-Host "      • Email: john.smith@academia.edu" -ForegroundColor White
        Write-Host "      • Password: password123" -ForegroundColor White
    }
    else {
        Write-Host "⚠️ Student Portal: STARTING (Vite typically takes 2-10 seconds)" -ForegroundColor Yellow
        Write-Host "   🌐 Expected URL: $frontendUrl/" -ForegroundColor Cyan
    }
    Write-Host ""
}

# Check Faculty Dashboard status
if (-not $StudentOnly -and -not $AdminOnly) {
    if (Test-PortInUse -Port $facultyDashboardPort) {
        Write-Host "✅ Faculty Dashboard: RUNNING" -ForegroundColor Green
        Write-Host "   🌐 Application: $facultyDashboardUrl/" -ForegroundColor Cyan
        Write-Host "   🔑 Demo Login:" -ForegroundColor Cyan
        Write-Host "      • Email: professor@zeus.academia" -ForegroundColor White
        Write-Host "      • Password: FacultyDemo2024!" -ForegroundColor White
    }
    else {
        Write-Host "⚠️ Faculty Dashboard: STARTING (Vite typically takes 2-10 seconds)" -ForegroundColor Yellow
        Write-Host "   🌐 Expected URL: $facultyDashboardUrl/" -ForegroundColor Cyan
    }
    Write-Host ""
}

# Check Admin Interface status
if ($AdminOnly -or (-not $StudentOnly -and -not $FacultyOnly)) {
    if (Test-PortInUse -Port $adminInterfacePort) {
        Write-Host "✅ Admin Interface: RUNNING" -ForegroundColor Green
        Write-Host "   🌐 Application: $adminInterfaceUrl/" -ForegroundColor Cyan
        Write-Host "   🔑 Demo Login:" -ForegroundColor Cyan
        Write-Host "      • Email: admin@zeus.academia" -ForegroundColor White
        Write-Host "      • Password: AdminDemo2024!" -ForegroundColor White
    }
    else {
        Write-Host "⚠️ Admin Interface: STARTING (Vite typically takes 2-10 seconds)" -ForegroundColor Yellow
        Write-Host "   🌐 Expected URL: $adminInterfaceUrl/" -ForegroundColor Cyan
    }
    Write-Host ""
}

Write-Host "🏁 STARTUP COMPLETE" -ForegroundColor Green
Write-Host "===================" -ForegroundColor Green
Write-Host "🎯 Next Steps:" -ForegroundColor Yellow

if (-not $FacultyOnly -and -not $AdminOnly) {
    Write-Host "   📚 Student Portal: $frontendUrl" -ForegroundColor White
}
if (-not $StudentOnly -and -not $AdminOnly) {
    Write-Host "   👨‍🏫 Faculty Dashboard: $facultyDashboardUrl" -ForegroundColor White
}
if ($AdminOnly -or (-not $StudentOnly -and -not $FacultyOnly)) {
    Write-Host "   🔐 Admin Interface: $adminInterfaceUrl" -ForegroundColor White
}

Write-Host "   🔧 API Health Check: $apiUrl/health" -ForegroundColor White
Write-Host ""
Write-Host "📋 Management Commands:" -ForegroundColor Yellow
Write-Host "   • View API health: Invoke-RestMethod $apiUrl/health" -ForegroundColor White
Write-Host "   • Stop services: Get-Job | Stop-Job; Get-Job | Remove-Job" -ForegroundColor White

$portList = "$apiPort"
if (-not $FacultyOnly -and -not $AdminOnly) { $portList += " :$frontendPort" }
if (-not $StudentOnly -and -not $AdminOnly) { $portList += " :$facultyDashboardPort" }
if ($AdminOnly -or (-not $StudentOnly -and -not $FacultyOnly)) { $portList += " :$adminInterfacePort" }
Write-Host "   • Check ports: netstat -ano | findstr ':$portList'" -ForegroundColor White
Write-Host ""

# Store job information for cleanup
$jobsHash = @{
    API       = $apiJob
    StartTime = Get-Date
}

if (-not $FacultyOnly -and -not $AdminOnly) {
    $jobsHash.StudentPortal = $frontendJob
}
if (-not $StudentOnly -and -not $AdminOnly) {
    $jobsHash.FacultyDashboard = $facultyJob
}
if ($AdminOnly -or (-not $StudentOnly -and -not $FacultyOnly)) {
    $jobsHash.AdminInterface = $adminJob
}

$Global:ZeusJobs = $jobsHash

if ($WaitForExit) {
    Write-Host "⏸️ Press Ctrl+C to stop services..." -ForegroundColor Yellow
    try {
        # Wait for user interrupt
        while ($true) {
            Start-Sleep -Seconds 1

            # Check if any jobs are still running
            $runningJobs = $jobsHash.Values | Where-Object { $_ -is [System.Management.Automation.Job] -and $_.State -eq 'Running' }
            if ($runningJobs.Count -eq 0) {
                Write-Host "⚠️ All services have stopped" -ForegroundColor Yellow
                break
            }
        }
    }
    catch {
        Write-Host "🛑 Shutting down services..." -ForegroundColor Yellow
    }
    finally {
        # Cleanup jobs
        Write-Host "🧹 Cleaning up background jobs..." -ForegroundColor Gray
        $jobsToClean = $jobsHash.Values | Where-Object { $_ -is [System.Management.Automation.Job] }
        Stop-Job $jobsToClean -ErrorAction SilentlyContinue
        Remove-Job $jobsToClean -ErrorAction SilentlyContinue
        Write-Host "✅ Cleanup complete" -ForegroundColor Green
    }
}
else {
    Write-Host "🔧 Services are running in background jobs" -ForegroundColor Cyan
    Write-Host "   Use 'Get-Job' to check status" -ForegroundColor Gray
    Write-Host "   Use 'Get-Job | Stop-Job; Get-Job | Remove-Job' to stop all services" -ForegroundColor Gray
}

Write-Host ""
$serviceNames = @()
if (-not $FacultyOnly -and -not $AdminOnly) { $serviceNames += "Student Portal" }
if (-not $StudentOnly -and -not $AdminOnly) { $serviceNames += "Faculty Dashboard" }
if ($AdminOnly -or (-not $StudentOnly -and -not $FacultyOnly)) { $serviceNames += "Admin Interface" }

$serviceText = if ($serviceNames.Count -eq 2) { "$($serviceNames[0]) and $($serviceNames[1]) are" }
elseif ($serviceNames.Count -eq 1) { "$($serviceNames[0]) is" }
else { "services are" }
Write-Host "🎉 Zeus Academia $serviceText ready!" -ForegroundColor Green
