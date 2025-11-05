<#
Process-Killer-TaskDialog.ps1 (Scaled Version)
- Bigger UI for easier reading.
- Same functionality as original.
#>

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Log helper
$LogPath = Join-Path $env:USERPROFILE "KillExplorerLog.txt"
function Write-Log([string]$line) {
    $ts = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $entry = "[$ts] $line"
    Add-Content -Path $LogPath -Value $entry -Encoding UTF8
}

function Get-ProcessList {
    Get-Process | Sort-Object -Property ProcessName,Id | Select-Object -Property ProcessName,Id
}

function Format-ResultsDialog([array]$results) {
    $sb = New-Object System.Text.StringBuilder
    foreach ($r in $results) {
        $line = "{0} : {1} (PID {2})" -f $r.Status.PadRight(7), $r.Name, $r.Pid
        [void]$sb.AppendLine($line)
    }
    return $sb.ToString()
}

# -------------------
# CREATE CONTROLS
# -------------------

$form = New-Object System.Windows.Forms.Form
$form.Text = "Process Selector - What do you want to select?"
$form.StartPosition = "CenterScreen"
$form.Topmost = $false
$form.Font = New-Object System.Drawing.Font("Segoe UI",10)

# Set size after creation
$form.Size = New-Object System.Drawing.Size(950,650)

# Label
$lbl = New-Object System.Windows.Forms.Label
$lbl.Text = "What do you want to select?"
$lbl.AutoSize = $true
$lbl.Font = New-Object System.Drawing.Font("Segoe UI",12,[System.Drawing.FontStyle]::Bold)
$lbl.Location = New-Object System.Drawing.Point(12,10)
$form.Controls.Add($lbl)

# ListView
$lv = New-Object System.Windows.Forms.ListView
$lv.View = 'Details'
$lv.FullRowSelect = $true
$lv.GridLines = $true
$lv.MultiSelect = $true
$lv.Width = 910
$lv.Height = 420
$lv.Location = New-Object System.Drawing.Point(12,45)

$col1 = New-Object System.Windows.Forms.ColumnHeader
$col1.Text = "Process Name"
$col1.Width = 700
$col2 = New-Object System.Windows.Forms.ColumnHeader
$col2.Text = "PID"
$col2.Width = 180
$lv.Columns.Add($col1) | Out-Null
$lv.Columns.Add($col2) | Out-Null
$form.Controls.Add($lv)

# Warning label
$warn = New-Object System.Windows.Forms.Label
$warn.Text = "WARNING: ANYTHING CRITICAL WILL CRASH THE DEVICE. ANY DATA WILL BE LOST ON ($env:COMPUTERNAME) WHEN KILLING CRITICAL PROCESSES. USE WITH CAUTION."
$warn.AutoSize = $false
$warn.Width = 910
$warn.Height = 60
$warn.Location = New-Object System.Drawing.Point(12,475)
$warn.Font = New-Object System.Drawing.Font("Segoe UI",10,[System.Drawing.FontStyle]::Bold)
$warn.ForeColor = 'DarkRed'
$warn.TextAlign = 'MiddleLeft'
$form.Controls.Add($warn)

# Checkbox
$chkKillOther = New-Object System.Windows.Forms.CheckBox
$chkKillOther.Text = "Kill other process"
$chkKillOther.AutoSize = $true
$chkKillOther.Location = New-Object System.Drawing.Point(12,540)
$form.Controls.Add($chkKillOther)

# Buttons
$btnRefresh = New-Object System.Windows.Forms.Button
$btnRefresh.Text = "Refresh list"
$btnRefresh.Width = 140
$btnRefresh.Location = New-Object System.Drawing.Point(600,535)
$form.Controls.Add($btnRefresh)

$btnKill = New-Object System.Windows.Forms.Button
$btnKill.Text = "Attempt Kill"
$btnKill.Width = 140
$btnKill.Location = New-Object System.Drawing.Point(760,535)
$form.Controls.Add($btnKill)

$btnOpenLog = New-Object System.Windows.Forms.Button
$btnOpenLog.Text = "Open Log"
$btnOpenLog.Width = 140
$btnOpenLog.Location = New-Object System.Drawing.Point(600,580)
$form.Controls.Add($btnOpenLog)

$btnExit = New-Object System.Windows.Forms.Button
$btnExit.Text = "Exit"
$btnExit.Width = 140
$btnExit.Location = New-Object System.Drawing.Point(760,580)
$form.Controls.Add($btnExit)

# -------------------
# FUNCTIONS
# -------------------

function Populate-List {
    $lv.Items.Clear()
    try {
        $procs = Get-ProcessList
        foreach ($p in $procs) {
            $item = New-Object System.Windows.Forms.ListViewItem($p.ProcessName)
            $item.SubItems.Add([string]$p.Id) | Out-Null
            $lv.Items.Add($item) | Out-Null
        }
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Failed to enumerate processes: $($_.Exception.Message)","Error",[System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
        Write-Log "Failed to enumerate processes: $($_.Exception.Message)"
    }
}

Populate-List

# -------------------
# EVENTS
# -------------------

$btnRefresh.Add_Click({ Populate-List })

$btnOpenLog.Add_Click({
    if (Test-Path $LogPath) { Start-Process notepad.exe -ArgumentList $LogPath } else { [System.Windows.Forms.MessageBox]::Show("Log not found.`n$LogPath","Info",[System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null }
})

$btnKill.Add_Click({
    if ($lv.SelectedItems.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("Select one or more processes first.","No selection",[System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
        return
    }

    $selected = @()
    foreach ($it in $lv.SelectedItems) {
        $name = $it.Text
        $pid = [int]$it.SubItems[1].Text
        if (-not $chkKillOther.Checked) {
            if ($name -ieq "explorer" -or $name -ieq "explorer.exe") { $selected += @{Name=$name;Pid=$pid} }
        } else {
            $selected += @{Name=$name;Pid=$pid}
        }
    }

    if ($selected.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("No valid process selected. Check 'Kill other process' to allow targeting other processes.","Nothing selected",[System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
        return
    }

    $confirmText = "WARNING: ANYTHING CRITICAL WILL EITHER CRASH THE DEVICE ($env:COMPUTERNAME).`n`n" +
                   "You are about to attempt to terminate the following process(es):`n" +
                   ($selected | ForEach-Object { " - $($_.Name) (PID $($_.Pid))" }) -join "`n" +
                   "`nProceed?"
    $resp = [System.Windows.Forms.MessageBox]::Show($confirmText, "Confirm Kill", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Warning)
    if ($resp -ne [System.Windows.Forms.DialogResult]::Yes) { return }

    $results = @()
    foreach ($t in $selected) {
        $name = $t.Name
        $pid = $t.Pid
        try {
            Stop-Process -Id $pid -Force -ErrorAction Stop
            $results += @{ Name=$name; Pid=$pid; Status="SUCCESS" }
            Write-Log "KILLED $name (PID $pid) via Stop-Process"
        } catch {
            $cmd = "taskkill /F /PID $pid"
            $out = & cmd /c $cmd 2>&1
            $exit = $LASTEXITCODE
            if ($exit -eq 0) {
                $results += @{ Name=$name; Pid=$pid; Status="SUCCESS" }
                Write-Log "KILLED $name (PID $pid) via taskkill"
                Write-Log "taskkill output: $($out -join ' ; ')"
            } else {
                $results += @{ Name=$name; Pid=$pid; Status="FAILED" }
                Write-Log "FAILED to kill $name (PID $pid) via taskkill. Exit=$exit"
                Write-Log "taskkill output: $($out -join ' ; ')"
            }
        }
    }

    $msg = Format-ResultsDialog($results)
    $anyFail = $results | Where-Object { $_.Status -ne "SUCCESS" }
    if ($anyFail) {
        $title = "Operation Completed -- Partial / Failed"
        [System.Windows.Forms.MessageBox]::Show($msg, $title, [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
    } else {
        $title = "Operation Completed -- Success"
        [System.Windows.Forms.MessageBox]::Show($msg, $title, [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
    }

    Populate-List
})

$btnExit.Add_Click({ $form.Close() })

# Ensure log exists
if (-not (Test-Path $LogPath)) { New-Item -Path $LogPath -ItemType File -Force | Out-Null }
Write-Log "UI opened on $env:COMPUTERNAME. User launched Process-Killer-TaskDialog."

[void]$form.ShowDialog()
Write-Log "UI closed."
