#!/bin/bash
# ###############################################
# Script has the following dependencies:
# 1. zip
# 2. azcopy
# 3. synthea
# ###############################################

echo ""
echo "Loading azd .env file from current environment"
echo ""

while IFS='=' read -r key value; do
    value=$(echo "$value" | sed 's/^"//' | sed 's/"$//')
    export "$key=$value"
    echo "$key=$value"
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
echo -e "\033[34mEnter the number of syntheic patients to generate (#) <press Enter to accept default> ["$defPatientNum"]:\033[0m"
read patientNum 
if [ -z "$patientNum" ] ; then
    patientNum=$defPatientNum
fi
[[ "${patientNum:?}" ]]
echo -e "\033[32mYou entered '$patientNum' patient(s).\033[0m"
# validate the input is a number
if ! [[ $patientNum =~ ^[0-9]+$ ]] ; then
    echo -e "\033[31mInvalid entry. Enter a number.\033[0m"
    exit 0
fi
echo ""

# other synthea options
echo -e "\033[34mEnter other Synthea options <press Enter to skip>, e.g.
         [-s seed]
         [-cs clinicianSeed]
         [-p populationSize]
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
echo -e "\033[34mGenerate as bulk (ndjson) data? (Y/N) <press Enter to accept default> ["$defIsNdjsonFormat"]:\033[0m"
read isNdjsonFormat
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
    echo -e "\033[34mCompress [zip] the bundle? <press Enter to accept default> ["$defIsBundleCompressed"]:\033[0m"
    read isBundleCompressed
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

echo "Generating synthetic patient data..."

# java -jar \
#     $SYNTHEA_JAR_PATH \
#     -p $patientNum \
#     -m $SYNTHEA_MODULE \
#     --exporter.fhir.bulk_data=$( [[ ${isNdjsonFormat,,} =~ ^(y)$ ]] && echo "True" || echo "False") 

java -jar \
    $SYNTHEA_JAR_PATH \
    -p $patientNum \
    $otherSyntheaOpts \
    --exporter.fhir.bulk_data=$( [[ ${isNdjsonFormat,,} =~ ^(y)$ ]] && echo "True" || echo "False") 


echo ""
echo "Patient data complete."
echo ""

# copy the generated data to the output folder in blob storage

if [[ ${isNdjsonFormat,,} =~ ^(n)$ && ${isBundleCompressed,,} =~ ^(y)$ ]]; then

    echo ""
    echo "...Compressing (zipping) FHIR bundles..."
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

echo -e "\033[32m...uploading to $destStorageAcct\033[0m"
echo ""

azcopy cp "$srcUploadDir/*.*" $destStorageAcct