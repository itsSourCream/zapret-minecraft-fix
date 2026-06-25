# Zapret Minecraft Fix

A PowerShell script to automatically patch [zapret](https://github.com/bol-van/zapret) (Windows version) configurations to fix Minecraft connection issues (port 25565).

## Features
- **Auto-Discovery**: Automatically finds the path to your zapret installation by tracking the running `winws.exe` process.
- **Supports All Strategies**: Patches all `general*.bat` configuration files found in the zapret folder.
- **Service Restart**: Automatically restarts the zapret service (if installed) to apply changes immediately without any extra steps.
- **Security**: Prompts for administrator privileges and preserves the original encoding of `.bat` files.

## Usage

You don't even need to download anything! Just open PowerShell and paste the following command:

```powershell
irm https://raw.githubusercontent.com/itsSourCream/zapret-minecraft-fix/main/main.ps1 | iex
```

The script will locate the necessary files (make sure zapret is running), insert port `25565` into the filter lists, append the DPI bypass rules, and restart zapret.

## Requirements
- Windows OS
- Installed and running zapret
- Administrator privileges
