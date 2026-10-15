@{
    RootModule           = 'ADHealth.psm1'
    ModuleVersion        = '0.1.0'
    GUID                 = '6f1d2c8e-4b7a-4e0f-9a43-2c5d7e8b9f10'
    Author               = 'Dan Newton'
    Description          = 'Read-only Active Directory object hygiene report.'
    PowerShellVersion    = '5.1'
    CompatiblePSEditions = @('Desktop', 'Core')
    FunctionsToExport    = @('Invoke-ADHealthReport')
    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @()
}
