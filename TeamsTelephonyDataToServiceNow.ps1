### RunBook to retrieve MS Teams telephony configuration and transfer it
### to ServiceNow's CMDB

### Parameters

$serviceNowInstance = Get-AutomationVariable -Name "ServiceNowInstanceName"
$teamsCred = Get-AutomationPSCredential -Name "Teams"
$serviceNowCred = Get-AutomationPSCredential -Name "ServiceNow"


Connect-MicrosoftTeams -Credential $teamsCred


### Retrieve line details

# $teamsData = Get-CsOnlineUser -Filter {UserPrincipalName -eq "tdbrody@soton.ac.uk"} | Select-Object UserPrincipalName,Department,OnPremLineURI,LineURI
$teamsData = Get-CsOnlineUser -Filter {OnPremLineUri -like "tel:*"} | Select-Object UserPrincipalName,Department,OnPremLineURI,LineURI

$json = ConvertTo-Json @{"records" = $teamsData}

### Send the line details to ServiceNow


Invoke-WebRequest -Uri "https://$serviceNowInstance.service-now.com/api/now/import/u_imp_ms_teams_extension/insertMultiple" -Method POST -ContentType "application/json" -Body $json -Credential $serviceNowCred -UseBasicParsing

### Retrieve the call queues

$queues = Get-CsCallQueue -WarningAction SilentlyContinue

$queuesOut = @()

foreach ($queue in $queues) {
    #Write-Output $queue.Identity

    $agentsChunk = @()
    $agents = @()
    
    # loop through agents at upto 15 at a time and find their upn
    foreach ($agent in $queue.Agents) {
        $agentsChunk += $agent.ObjectId
        if (($agentsChunk.Length -eq 15) -or ($agent -eq $queue.Agents[-1])) {
            $filter = ($agentsChunk | ForEach-Object { "ObjectId -eq '$_'" }) -join ' -or '
            Get-CsOnlineUser -Filter $filter | Select-Object -Property UserPrincipalName | ForEach-Object { $agents += $_.UserPrincipalName }
            $agentsChunk = @()
        }
    }
    
    # lookup the upn + phone number for each application instance
    $applications = $queue.ApplicationInstances | ForEach-Object {
        Get-CsOnlineApplicationInstance -Identity $_ | Select-Object -Property UserPrincipalName, PhoneNumber
    }

    # create an entry for each application instance
    foreach ($application in $applications) {
        $queueOut = @{
            "Agents" = $agents -join ","
            "UserPrincipalName" = $application.UserPrincipalName
            "PhoneNumber" = $application.PhoneNumber
            "RoutingMethod" = $queue.RoutingMethod.Value
            "Name" = $queue.Name
        }
        $queuesOut += $queueOut
    }

}

### Send the queues to ServiceNow

$json = ConvertTo-Json @{"records" = $queuesOut}

Invoke-WebRequest -Uri "https://$serviceNowInstance.service-now.com/api/now/import/u_import_ms_teams_call_queues/insertMultiple" -Method POST -ContentType "application/json" -Body $json -Credential $serviceNowCred -UseBasicParsing


Disconnect-MicrosoftTeams