#================================================================================================================
#
# Script purpose : Collect Intune Device event logs, files and folders and upload them on Azure File Share
# Author 		 : Damien VAN ROBAEYS
# Twitter 		 : @syst_and_deploy
# Blog 		     : http://www.systanddeploy.com/
#
#================================================================================================================

$Current_Folder = split-path $MyInvocation.MyCommand.Path
$xml = "$Current_Folder\Azure_Infos.xml"
$my_xml = [xml] (Get-Content $xml)
$Azure_resourceGroupName = $my_xml.Configuration.Azure_resourceGroupName
$Azure_storageAccName = $my_xml.Configuration.Azure_storageAccName
$Azure_fileShareName = $my_xml.Configuration.Azure_fileShareName
$ApplicationId = $my_xml.Configuration.ApplicationId
$TenantId = $my_xml.Configuration.TenantId

$SystemRoot = $env:SystemRoot
$CompName = $env:computername

$Get_Day_Date = Get-Date -Format "yyyyMMdd"
$Log_File = "$SystemRoot\Debug\Collect_Device_Content_$CompName" + "_$Get_Day_Date.log"
$Logs_Collect_Folder = "C:\Device_Logs_From" + "_$CompName" + "_$Get_Day_Date"
$Logs_Collect_Folder_ZIP = "$Logs_Collect_Folder" + ".zip"

$EVTX_files = "$Logs_Collect_Folder\EVTX_Files"
$Logs_Folder = "$Logs_Collect_Folder\All_logs"

$ProgData = $env:ProgramData
$Content_to_collect_File = "$Current_Folder\Content_to_collect.xml"
$Content_to_collect_XML = [xml] (Get-Content $Content_to_collect_File)

If(!(test-path $Logs_Collect_Folder)){new-item $Logs_Collect_Folder -type Directory -force | out-null}
If(!(test-path $EVTX_files)){new-item $EVTX_files -type Directory -force | out-null}
If(!(test-path $Log_File)){new-item $Log_File -type file -force | out-null}
If(!(test-path $Logs_Folder)){new-item $Logs_Folder -type Directory -force | out-null}

Function Write_Log
	{
		param(
		$Message_Type,	
		$Message
		)
		
		$MyDate = "[{0:MM/dd/yy} {0:HH:mm:ss}]" -f (Get-Date)		
		Add-Content $Log_File  "$MyDate - $Message_Type : $Message"			
	}
	
Function Export_Event_Logs
	{
		param(
		$Log_To_Export,	
		$Log_Output,
		$File_Name
		)	
		
		Add-content $Log_File ""	
		Write_Log -Message_Type "INFO" -Message "Collecting logs from: $Log_To_Export"
		Try
			{
				WEVTUtil export-log $Log_To_Export "$Log_Output\$File_Name.evtx" | out-null	
				Write_Log -Message_Type "SUCCESS" -Message "Event log $File_Name.evtx has been successfully exported"
			}
		Catch
			{
				Write_Log -Message_Type "ERROR" -Message "An issue occured while exporting event log $File_Name.evtx"
			}
	}	
	
	
Function Export_Logs_Files_Folders
	{
		param(
		$Log_To_Export,	
		$Log_Output
		)	
		
		Add-content $Log_File ""			
		If(test-path $Log_To_Export)
			{
				$Content_Name = Get-Item $Log_To_Export
				Try
					{
						Copy-Item $Log_To_Export $Log_Output -Recurse -Force
						Write_Log -Message_Type "SUCCESS" -Message "The folder $Content_Name has been successfully copied"													
					}
				Catch
					{
						Write_Log -Message_Type "ERROR" -Message "An issue occured while copying the folder $Content_Name"																				
					}
			}
		Else
			{
				Write_Log -Message_Type "ERROR" -Message "The following path does not exist: $Log_To_Export"			
			}
	}	


Write_Log -Message_Type "INFO" -Message "Starting collecting Intune logs on $CompName"

Add-content $Log_File ""
Add-content $Log_File "---------------------------------------------------------------------------------------------------------"
Write_Log -Message_Type "INFO" -Message "Step 1 - Collecting event logs"
Add-content $Log_File "---------------------------------------------------------------------------------------------------------"	
$Events_To_Check = $Content_to_collect_XML.Content_to_collect.Event_Logs.Event_Log
ForEach($Event in $Events_To_Check)
	{
		$Event_Name = $Event.Event_Name
		$Event_Path = $Event.Event_Path	
		Export_Event_Logs -Log_To_Export $Event_Path -Log_Output $EVTX_files -File_Name $Event_Name		
	}
	
	
Add-content $Log_File ""
Add-content $Log_File "---------------------------------------------------------------------------------------------------------"
Write_Log -Message_Type "INFO" -Message "Step 2 - Copying files and folders"
Add-content $Log_File "---------------------------------------------------------------------------------------------------------"	
$Folder_To_Check = $Content_to_collect_XML.Content_to_collect.Folders.Folder_Path
ForEach($Explorer_Content in $Folder_To_Check)
	{		
		Export_Logs_Files_Folders -Log_To_Export $Explorer_Content -Log_Output $Logs_Folder		
	}	


Add-content $Log_File ""
Add-content $Log_File "---------------------------------------------------------------------------------------------------------"
Write_Log -Message_Type "INFO" -Message "Step 3 - Creating the ZIP with logs"
Add-content $Log_File "---------------------------------------------------------------------------------------------------------"
Try
	{
		Add-Type -assembly "system.io.compression.filesystem"
		[io.compression.zipfile]::CreateFromDirectory($Logs_Collect_Folder, $Logs_Collect_Folder_ZIP) 
		Write_Log -Message_Type "SUCCESS" -Message "The ZIP file has been successfully created"	
		Write_Log -Message_Type "INFO" -Message "The ZIP is located in :$Logs_Collect_Folder_ZIP"				
	}
Catch
	{
		Write_Log -Message_Type "ERROR" -Message "An issue occured while creating the ZIP file"		
	}
 
 
Add-content $Log_File ""
Add-content $Log_File "---------------------------------------------------------------------------------------------------------"
Write_Log -Message_Type "INFO" -Message "Step 4 - Importing certificate"
Add-content $Log_File "---------------------------------------------------------------------------------------------------------"
  
$Certificate_Path = "$Current_Folder\intune_cert.pfx"
[Byte[]] $Encrypt_key = (1..16)
$Cert_PWD_File = "$Current_Folder\cert_import.txt"
$secureString = Get-Content $Cert_PWD_File | ConvertTo-SecureString -Key $Encrypt_key
 
Try
	{
		Import-PfxCertificate -FilePath $Certificate_Path -CertStoreLocation Cert:\LocalMachine\My -Password $secureString  
		Write_Log -Message_Type "SUCCESS" -Message "The certificate has been successfully imported"	
		$Certificate_Status = "OK"		
	}
Catch
	{
		Write_Log -Message_Type "ERROR" -Message "An issue occured while importing certificate"	
		$Certificate_Status = "KO"		
	}	 
 
 
If($Certificate_Status -eq "OK")
	{	
		Add-content $Log_File ""
		Add-content $Log_File "---------------------------------------------------------------------------------------------------------"
		Write_Log -Message_Type "INFO" -Message "Step 5 - Installing Azure module"
		Add-content $Log_File "---------------------------------------------------------------------------------------------------------"
		
		Try
			{
				Install-PackageProvider -Name NuGet -RequiredVersion 2.8.5.201 -Force 			
				Install-Module -Name Az -AllowClobber -force -confirm:$false -ErrorAction SilentlyContinue 
				Write_Log -Message_Type "SUCCESS" -Message "Az module has been successfully installed"	
				$Az_Module_Status = "OK"		
			}
		Catch
			{
				Write_Log -Message_Type "ERROR" -Message "An issue occured while installing module"	
				$Az_Module_Status = "KO"		
			}			
	}	 
 
 
If($Az_Module_Status -eq "OK")
	{ 
		Add-content $Log_File ""
		Add-content $Log_File "---------------------------------------------------------------------------------------------------------"
		Write_Log -Message_Type "INFO" -Message "Step 6 - Connecting to Azure"
		Add-content $Log_File "---------------------------------------------------------------------------------------------------------"
		Try
			{
				$Get_Current_Cert = Get-ChildItem -Path Cert:\LocalMachine\My\ | Where-Object {$_.Subject -match "IntuneLogCert"}
				$Thumbprint = $Get_Current_Cert.Thumbprint
				Connect-AzAccount -CertificateThumbprint $Thumbprint -ApplicationId $ApplicationId -Tenant $TenantId -ServicePrincipal
				Write_Log -Message_Type "SUCCESS" -Message "Authentification OK to Azure"	
				$Azure_Status = "OK"		
			}
		Catch
			{
				Write_Log -Message_Type "ERROR" -Message "Authentification KO to Azure"	
				$Azure_Status = "KO"		
			}	 
		 
		 
		If($Azure_Status -eq "OK")
			{
				$folderPath="/"  	
				Add-content $Log_File ""
				Add-content $Log_File "---------------------------------------------------------------------------------------------------------"
				Write_Log -Message_Type "INFO" -Message "Step 7 - Uploading the ZIP to Azure file share"
				Add-content $Log_File "---------------------------------------------------------------------------------------------------------"
				Try
					{
						$ctx=(Get-AzStorageAccount -ResourceGroupName $Azure_resourceGroupName -Name $Azure_storageAccName).Context  
						$fileShare=Get-AZStorageShare -Context $ctx -Name $Azure_fileShareName  
						Set-AzStorageFileContent -Share $fileShare -Source $Logs_Collect_Folder_ZIP -Path $folderPath -Force 
						Write_Log -Message_Type "SUCCESS" -Message "The ZIP file has been correctly uploaded to Azure file share"	
					}
				Catch
					{
						Write_Log -Message_Type "ERROR" -Message "An issue occured while uploading ZIP file"	
					}
				Disconnect-AzAccount 					
			}
				
			Add-content $Log_File ""
			Add-content $Log_File "---------------------------------------------------------------------------------------------------------"
			Write_Log -Message_Type "INFO" -Message "Step 8 - Removing certificate"
			Add-content $Log_File "---------------------------------------------------------------------------------------------------------"
			
			Try
				{
					$Get_Current_Cert | Remove-Item 
					Write_Log -Message_Type "SUCCESS" -Message "The certificate has been correctly removed"	
				}
			Catch
				{
					Write_Log -Message_Type "ERROR" -Message "An issue occured while removing the certificate"	
				}							
	}
	
Add-content $Log_File ""
Add-content $Log_File "---------------------------------------------------------------------------------------------------------"
Write_Log -Message_Type "INFO" -Message "Step 9 - Removing temp collect folder and ZIP"
Add-content $Log_File "---------------------------------------------------------------------------------------------------------"

Try
	{
		Remove-Item $Logs_Collect_Folder -Recurse -Force
		Remove-Item $Logs_Collect_Folder_ZIP -Recurse -Force		
		Write_Log -Message_Type "SUCCESS" -Message "The collect folders have been removed"	
	}
Catch
	{
		Write_Log -Message_Type "ERROR" -Message "An issue occured while removing log collect folder"	
	}		