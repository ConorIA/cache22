param(
    [string]$Namespace = "root\cimv2",
    [Parameter(Mandatory = $true)] [string]$Class,
    [string]$Filter,
    [string]$Properties
)

# 
[string[]]$propertyList = if ($Properties) {
    $Properties.Split(",") | ForEach-Object { $_.Trim() }
}
else {
    @()
}

#  Get-Cimresult
$isSupportCim = [bool](Get-Command Get-Cimresult -ErrorAction SilentlyContinue)

# 
$queryParams = @{ Namespace = $Namespace }
if ($isSupportCim) { $queryParams.ClassName = $Class } else { $queryParams.Class = $Class }
if ($Filter) { $queryParams.Filter = $Filter }

# 
# CIM 
# WIM 
if ($isSupportCim -and $propertyList.Count -gt 0) {
    $queryParams.Property = $propertyList
}

# 
$results = if ($isSupportCim) { Get-Cimresult @queryParams } else { Get-WmiObject @queryParams }

# 
foreach ($result in $results) {
    # 
    foreach ($property in $result.PSObject.Properties) {
        $name = $property.Name
        $value = $property.Value

        # 
        if ($name.StartsWith("__") -or $name -eq "CimresultProperties" -or $name -eq "CimClass") { continue }

        #  propertyList 
        # propertyList 
        if ($propertyList.Count -eq 0 -or $propertyList -contains $name) {

            #  wmic 
            #  string  IEnumerable
            if ($value -isnot [string] -and $value -is [Collections.IEnumerable]) {
                $formattedValue = ($value | ForEach-Object { "`"$_`"" }) -join ","
                Write-Output "$name={$formattedValue}"
            }
            else {
                Write-Output "$name=$value"
            }
        }
    }
}
