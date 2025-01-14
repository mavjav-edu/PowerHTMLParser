#requires -module BuildHelpers
if (-not (Import-Module BuildHelpers -PassThru -verbose:$false -erroraction silentlycontinue)) {
    Install-Module buildhelpers -scope currentuser -erroraction stop -force
    Import-Module BuildHelpers -erroraction stop -verbose:$false
}
Set-BuildEnvironment -force
$BuildOutputProject = Join-Path $env:BHBuildOutput $env:BHProjectName
$ModuleManifestPath = Join-Path $BuildOutputProject '\*.psd1'

if (-not (Test-Path $ModuleManifestPath)) {throw "Module Manifest not found at $ModuleManifestPath. Did you run 'Invoke-Build Build' first?"}

Describe 'Powershell Module' {

    Context "$env:BHProjectName" {
        $ModuleName = $env:BHProjectName
        It 'Has a valid Module Manifest' {
            if ($isCoreCLR -or $PSVersionTable.PSVersion -ge [Version]"5.1") {
                $Script:Manifest = Test-ModuleManifest $ModuleManifestPath
            } else {
                #Copy the Module Manifest to a temp file in order to test to fix a bug where
                #Test-ModuleManifest caches the first result, thus not catching changes
                $TempModuleManifestPath = [System.IO.Path]::GetTempFileName() + '.psd1'
                Copy-Item $ModuleManifestPath $TempModuleManifestPath
                $Script:Manifest = Test-ModuleManifest $TempModuleManifestPath
                Remove-Item $TempModuleManifestPath -verbose:$false
            }
        }

        It 'Has a valid root module' {
            $Manifest.RootModule | Should Be "$ModuleName.psm1"
        }

        It 'Has a valid Description' {
            $Manifest.Description | Should Not BeNullOrEmpty
        }

        It 'Has a valid GUID' {
            [Guid]$Manifest.Guid | Should BeOfType 'System.GUID'
        }

        It 'Has a valid Copyright' {
            $Manifest.Copyright | Should Not BeNullOrEmpty
        }

        It 'Exports all public functions' {
            $FunctionFiles = Get-ChildItem "$BuildOutputProject\Public" -Filter *.ps1 | Select-Object -ExpandProperty BaseName
            $FunctionNames = $FunctionFiles | ForEach-Object {$_ -replace '-', "-$($Manifest.Prefix)"}
            $ExFunctions = $Manifest.ExportedFunctions.Values.Name
            foreach ($FunctionName in $FunctionNames)
            {
                $ExFunctions -contains $FunctionName | Should Be $true
            }
        }

        It 'Has at least 1 exported command' {
            $Script:Manifest.exportedcommands.count | Should BeGreaterThan 0
        }
        It 'Can be imported as a module successfully' {
            Remove-Module $ModuleName -ErrorAction SilentlyContinue
            Import-Module $BuildOutputProject -PassThru -verbose:$false -OutVariable BuildOutputModule | Should BeOfType System.Management.Automation.PSModuleInfo
            $BuildOutputModule.Name | Should Be $ModuleName
        }
        It 'Is visible in Get-Module' {
            $module = Get-Module $ModuleName
            $Module | Should BeOfType System.Management.Automation.PSModuleInfo
            $Module.Name | Should Be $ModuleName
        }
    }
}

Describe 'PSScriptAnalyzer' {
    $results = Invoke-ScriptAnalyzer -Path $BuildOutputProject -Recurse -ExcludeRule "PSAvoidUsingCmdletAliases","PSAvoidGlobalVars","PSReviewUnusedParameter" -Verbose:$false
    It 'PSScriptAnalyzer returns zero errors for all files in the repository' {
        $results
        $results.Count | Should Be 0
    }
}