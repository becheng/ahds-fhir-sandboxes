# Azure Health Data Services - FHIR Service with OSS FHIR Loader

This sample uses the oss-fhir-loader to seed FHIR Resources into an Azure Health Data Service FHIR Service.

## TODOs
1. use the latest synthea installation
2. Assumes developer is using bash 


## Prerequistes
Install the following:
1. [AzCopy](https://learn.microsoft.com/en-us/azure/storage/common/storage-use-azcopy-v10#download-azcopy)
2. [Synthea Patient Data Generator](https://github.com/synthetichealth/synthea?tab=readme-ov-file#installation)
3. zip, e.g. `sudo apt install zip`

## Instructions
1. Run the following script to create an Entra ID Service Principal and copy the output to be used later 
    ```
    # create an Entra ID app
    azCopyAppId=$(az ad app create --display-name "azCopyAppDeleteMe" --query "appId" -o tsv)

    # create an app secret 
    azCopyAppSecret=$(az ad app credential reset --id $azCopyAppId --display-name "client-secret" --query password -o tsv)

    # create the service principal
    az ad sp create --id $azCopyAppId

    azCopySPNObjectId=$(az ad sp list --all --query "[?appId=='$azCopyAppId'].id" -o tsv)

    echo "**********************************************"
    echo "azCopyAppSecret:   $azCopyAppSecret"
    echo "azCopySPNObjectId: $azCopySPNObjectId" 
    echo "**********************************************"
    ``` 
2. Add the secret as a user-defined azd env variable
    ```
    azd env set AZCOPY_SPA_CLIENT_SECRET $azCopyAppSecret
    ```
3. Record the path of your Synthea synthea-with-dependencies.jar, e.g. /<your-directory>/synthea/synthea-with-dependencies.jar
4. run `azd provision`
5. When prompted for the 'azCopySpnPrincipalId' value, enter the azCopySPNObjectId value above and enter Yes to save the value in the environment for future use.
6. When prompted for the 'syntheaJarPath' value, enter the Synthea path above and enter Yes to save the value in the environment for future use.
7. Enter the values when prompted to generate the Synthea Patient Data  


## Notes

### OSS FHIR Loader
The oss-fhir-loader supports the following formats:
- FHIR Bundles (transactional or batch).  Uses the "bundles" container in the storage account.
- NDJSON formated FHIR Bundles.  Uses the "ndjson" container in the storage account.
- Compressed (.zip) formatted FHIR Bundles.  Uses the "zip" container in the storage account.

### AHDS FHIR Service
The AHDS FHIR Service $import endpoint currenly only supports FHIR NDJSON bundles.  Ref: https://learn.microsoft.com/en-us/azure/healthcare-apis/fhir/import-data#body.
