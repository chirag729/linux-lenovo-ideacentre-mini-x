# windows-hardware-audit.ps1
# Run this on the Lenovo IdeaCentre Mini x while on Windows 11.
# Captures all hardware identification data for Linux device tree development.
#
# Usage: .\windows-hardware-audit.ps1 [-OutputDir <path>]

param(
    [string]$OutputDir = ".\hardware-audit-$(Get-Date -Format 'yyyyMMdd')"
)

Write-Host "=== Windows Hardware Audit for Lenovo IdeaCentre Mini x ===" -ForegroundColor Cyan
Write-Host "Output directory: $OutputDir"
Write-Host "Date: $(Get-Date -Format 'u')"
Write-Host ""

New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

function Capture {
    param([string]$Name, [scriptblock]$Command)
    Write-Host "Capturing: $Name ..."
    try {
        & $Command | Out-File -FilePath "$OutputDir\$Name" -Encoding UTF8
    } catch {
        "FAILED: $_" | Out-File -FilePath "$OutputDir\$Name" -Encoding UTF8
    }
}

# System identification
Capture "system-info.txt" {
    Get-CimInstance Win32_ComputerSystem | Format-List *
}
Capture "baseboard-info.txt" {
    Get-CimInstance Win32_BaseBoard | Format-List *
}
Capture "bios-info.txt" {
    Get-CimInstance Win32_BIOS | Format-List *
}
Capture "processor-info.txt" {
    Get-CimInstance Win32_Processor | Format-List *
}

# PnP devices (full enumeration)
Capture "pnp-devices-all.txt" {
    Get-PnpDevice | Format-Table Class, FriendlyName, InstanceId, Status -AutoSize
}
Capture "pnp-devices-ok.txt" {
    Get-PnpDevice | Where-Object {$_.Status -eq 'OK'} |
        Format-Table Class, FriendlyName, InstanceId -AutoSize
}

# PCI devices with hardware IDs
Capture "pci-devices.txt" {
    Get-PnpDevice | Where-Object {$_.InstanceId -like 'PCI*'} |
        ForEach-Object {
            Write-Output "=== $($_.FriendlyName) ==="
            Write-Output "  InstanceId: $($_.InstanceId)"
            Write-Output "  Class: $($_.Class)"
            Write-Output "  Status: $($_.Status)"
            $props = $_ | Get-PnpDeviceProperty -KeyName DEVPKEY_Device_HardwareIds -ErrorAction SilentlyContinue
            if ($props) {
                Write-Output "  HardwareIds: $($props.Data -join ', ')"
            }
            $loc = $_ | Get-PnpDeviceProperty -KeyName DEVPKEY_Device_LocationInfo -ErrorAction SilentlyContinue
            if ($loc) {
                Write-Output "  Location: $($loc.Data)"
            }
            Write-Output ""
        }
}

# USB devices
Capture "usb-devices.txt" {
    Get-PnpDevice | Where-Object {$_.InstanceId -like 'USB*'} |
        Format-Table InstanceId, FriendlyName, Class, Status -AutoSize
}
Capture "usb-controllers.txt" {
    Get-PnpDevice -Class USB | Format-List *
}

# Network adapters (WiFi, Ethernet, Bluetooth)
Capture "network-adapters.txt" {
    Get-NetAdapter | Format-List *
}
Capture "network-hardware.txt" {
    Get-NetAdapterHardwareInfo | Format-List *
}
Capture "wifi-info.txt" {
    netsh wlan show interfaces 2>&1
    netsh wlan show drivers 2>&1
}

# Display / GPU
Capture "display-adapters.txt" {
    Get-CimInstance Win32_VideoController | Format-List *
}
Capture "monitors.txt" {
    Get-CimInstance Win32_DesktopMonitor | Format-List *
}
Capture "display-pnp.txt" {
    Get-PnpDevice -Class Display | Format-List *
    Get-PnpDevice -Class Monitor | Format-List *
}

# Audio
Capture "audio-devices.txt" {
    Get-PnpDevice -Class AudioEndpoint | Format-List *
}
Capture "audio-media.txt" {
    Get-PnpDevice -Class Media | Format-List *
}

# Storage
Capture "disk-info.txt" {
    Get-Disk | Format-List *
}
Capture "partition-layout.txt" {
    Get-Partition | Format-Table DiskNumber, PartitionNumber, Type, Size, Offset, DriveLetter -AutoSize
}
Capture "volume-info.txt" {
    Get-Volume | Format-Table DriveLetter, FileSystemLabel, FileSystem, Size, SizeRemaining -AutoSize
}

# ACPI devices
Capture "acpi-devices.txt" {
    Get-PnpDevice | Where-Object {$_.InstanceId -like 'ACPI*'} |
        Format-Table InstanceId, FriendlyName, Status -AutoSize
}

# Firmware / Secure Boot
Capture "secureboot-info.txt" {
    try { Confirm-SecureBootUEFI } catch { "SecureBoot check failed: $_" }
}

# Full system report via systeminfo
Capture "systeminfo.txt" {
    systeminfo 2>&1
}

# Driver information
Capture "drivers.txt" {
    Get-CimInstance Win32_PnPSignedDriver |
        Where-Object {$_.DeviceName -ne $null} |
        Select-Object DeviceName, DriverVersion, Manufacturer, InfName |
        Format-Table -AutoSize
}

# Bluetooth
Capture "bluetooth-devices.txt" {
    Get-PnpDevice -Class Bluetooth | Format-List *
}

# Power/battery info (should show none for desktop)
Capture "power-info.txt" {
    Get-CimInstance Win32_Battery 2>&1
    powercfg /batteryreport /output "$OutputDir\battery-report.html" 2>&1
}

Write-Host ""
Write-Host "=== Audit complete ===" -ForegroundColor Green
Write-Host "Files saved to: $OutputDir"
$count = (Get-ChildItem -Path $OutputDir -File).Count
Write-Host "Total files: $count"
Get-ChildItem -Path $OutputDir | Format-Table Name, Length -AutoSize
