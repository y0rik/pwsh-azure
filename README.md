## Description
The repository contains powershell scripts helping with various Azure-related tasks

## How to use (in general)
Either script or its functions contain powershell-style built-in help

To get script-level help
```powershell
Get-Help <script>.ps1
```

To get function-level help
Import the script content (the first dot symbol is important) and use normal Get-Help
```powershell
. <script>.ps1
Get-Help <function>
```
### Install-AzAutomationModuleWithDependencies.ps1
Installs Azure automation account module with all dependencies recursively. Can be used with -ResolveOnly switch to resolve and show the dependencies

It contains a set of functions that can be imported into powershell session
```powershell
. Install-AzAutomationModuleWithDependencies.ps1
```
Run the installation
```powershell
Install-AzAutomationModuleWithDependencies AutomationAccountName 'SampleAutomation' -ResourceGroupName 'SampleRG' -ModuleName 'SampleModule'
```
Get help
```powershell
Get-Help Install-AzAutomationModuleWithDependencies
Get-Help Install-AzAutomationModuleWithDependencies -Examples
```

## Improvements/Questions/Issues
Feel free to submit via Issues