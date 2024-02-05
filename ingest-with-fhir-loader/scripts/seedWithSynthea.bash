#!/bin/bash
# ###############################################
# Script has the following dependencies:
# 1. zip
# 2. azcopy
# ###############################################

echo ""
echo "Loading azd .env file from current environment"
echo ""

while IFS='=' read -r key value; do
    value=$(echo "$value" | sed 's/^"//' | sed 's/"$//')
    export "$key=$value"
    #echo "$key=$value"
done <<EOF
$(azd env get-values)
EOF

# get azCopyApplicationId from the SPN object Id
export AZCOPY_SPA_APPLICATION_ID=$(az ad sp list --all --query "[?id=='$AZCOPY_SPN_OBJECT_ID'].appId" -o tsv)

echo "Environment variables set."
echo ""

declare defPatientNum="10" #default
declare patientNum=""

# declare defOtherSyntheaOpts="" #default
declare otherSyntheaOpts=""

declare defIsNdjsonFormat="N" #default
declare isNdjsonFormat=""

declare defIsBundleCompressed="N" #default
declare isBundleCompressed=""

declare srcUploadDir=""
declare destContainer=""
declare destStorageAcct=""  

echo "Preparing Synthea Patient Data...."
echo ""

# prompt patient number
read -ep $'\033[34mEnter the number of syntheic patients to generate (#) <press Enter to accept default> ['$defPatientNum$']:\033[0m' patientNum
#read patientNum 
if [ -z "$patientNum" ] ; then
    patientNum=$defPatientNum
fi
[[ "${patientNum:?}" ]]
echo -e "\033[32mYou entered '$patientNum' patient(s).\033[0m"
# validate the input is a number
if ! [[ $patientNum =~ ^[0-9]+$ ]] ; then
    echo -e "\033[31mInvalid entry. Enter a valid number.\033[0m"
    exit 0
fi
echo ""

# other synthea options
echo -e "\033[34mEnter other Synthea options <press Enter to skip>, e.g.
    [-s seed]
    [-cs clinicianSeed]
    [-p populationSize]
    [-m syntheaModule]
    [-r referenceDate as YYYYMMDD]
    [-g gender]
    [-a minAge-maxAge]
    [-o overflowPopulation]
    [-c localConfigFilePath]
    [-d localModulesDirPath]
    [-i initialPopulationSnapshotPath]
    [-u updatedPopulationSnapshotPath]
    [-t updateTimePeriodInDays]
    [-f fixedRecordPath]
    [-k keepMatchingPatientsPath]
    [state [city]]:\033[0m"
read otherSyntheaOpts 
if [ -z "$otherSyntheaOpts" ] ; then
    otherSyntheaOpts=""
fi
# [[ "${otherSyntheaOpts:?}" ]]
echo -e "\033[32mYou entered '$otherSyntheaOpts'.\033[0m"
echo ""

# prompt to bundle or not
read -ep $'\033[34mGenerate as bulk (ndjson) data? (Y/N) <press Enter to accept default> ['$defIsNdjsonFormat$']:\033[0m' isNdjsonFormat
# read 
if [ -z "$isNdjsonFormat" ] ; then
    isNdjsonFormat=$defIsNdjsonFormat
fi
[[ "${isNdjsonFormat:?}" ]]
echo -e "\033[32mYou entered '$isNdjsonFormat' to generate a bulk (ndjson) bundle.\033[0m"
if [[ ! ${isNdjsonFormat,,} =~ ^(y|n)$ ]] ; then
    echo -e "\033[31mInvalid input. Enter either Y or N.\033[0m"
    exit 0
fi
echo ""

# prompt to zip the bundle if not ndjson bundles
if [[ ${isNdjsonFormat,,} =~ ^(n)$ ]]; then
    read -ep $'\033[34mCompress [zip] the bundle? <press Enter to accept default> ['$defIsBundleCompressed$']:\033[0m' isBundleCompressed
    #read isBundleCompressed
fi
# otherwise default to its default value
if [ -z "$isBundleCompressed" ]; then
    isBundleCompressed=$defIsBundleCompressed
fi
[[ "${isBundleCompressed:?}" ]]
if [[ ${isNdjsonFormat,,} =~ ^(n)$ ]]; then
    echo -e "\033[32mYou entered '$isBundleCompressed' to compress the bundle.\033[0m"
fi
if [[ ! ${isBundleCompressed,,} =~ ^(y|n)$ ]] ; then
    echo -e "\033[31mInvalid input. Enter either Y or N.\033[0m"
    exit 0
fi
echo ""

echo ""
echo -e "\033[32mGenerating synthetic patient data...\033[0m"

if ! [ -f ./synthea-with-dependencies.jar ]; then
    echo "Downloaidng the latest synthea-with-dependencies.jar..."
    wget "https://github.com/synthetichealth/synthea/releases/download/master-branch-latest/synthea-with-dependencies.jar"
fi

java -jar \
    ./synthea-with-dependencies.jar \
    -p $patientNum \
    $otherSyntheaOpts \
    --exporter.fhir.bulk_data=$( [[ ${isNdjsonFormat,,} =~ ^(y)$ ]] && echo "True" || echo "False") 


echo ""
echo -e "\033[32m...Patient data generation complete!\033[0m"

echo ""

# copy the generated data to the output folder in blob storage

if [[ ${isNdjsonFormat,,} =~ ^(n)$ && ${isBundleCompressed,,} =~ ^(y)$ ]]; then

    echo ""
    echo -e "\033[32mCompressing (zipping) FHIR bundles...\033[0m"
    mkdir -p "output/zip"
    # sudo apt-get install zip
    zip output/zip/compressedFhirBundles.zip output/fhir/*.*

    srcUploadDir="output/zip"
    destContainer="zip"

elif [[ ${isNdjsonFormat,,} =~ ^(y)$ ]]; then

    srcUploadDir="output/fhir"  
    destContainer="ndjson"

else

    srcUploadDir="output/fhir"  
    destContainer="bundles"

fi

destStorageAcct="https://$STORAGE_ACCOUNT_NAME.blob.core.windows.net/$destContainer/"

echo -e "\033[32m...Uploading to $destStorageAcct\033[0m"
echo ""

azcopy cp "$srcUploadDir/*.*" $destStorageAcct