$ErrorActionPreference = "Stop"

$projectPath = Join-Path $PSScriptRoot ".."
$projectPath = (Resolve-Path $projectPath).Path

Write-Host "Runtime project path: $projectPath"

$godotCmd = Get-Command godot -ErrorAction SilentlyContinue
if (-not $godotCmd) {
    Write-Host "Godot is not on PATH. Install Godot 4 and rerun this script."
    exit 2
}

Write-Host "Running headless project parse check..."
& godot --headless --path $projectPath --quit

Write-Host "Headless checks completed."
