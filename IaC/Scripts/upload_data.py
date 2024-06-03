import sys
import os

from azure.storage.blob import BlobServiceClient

def upload_data(AZURESACS, SA_CONTAINER):
    blob_service_client = BlobServiceClient.from_connection_string(AZURESACS)
    container_client = blob_service_client.get_container_client(SA_CONTAINER)
    blob_client = container_client.get_blob_client("data.json")
    file_path = os.getcwd() + '\Scripts\data.json'
    with open(file_path, 'rb') as data:
        blob_client.upload_blob(data, blob_type="BlockBlob",overwrite=True)
        data.close()
    if os.path.exists(file_path):
        os.remove(file_path)
    else:
        return

if __name__== "__main__":
    AZURESACS = sys.argv[1]
    SA_CONTAINER = sys.argv [2]
    upload_data(AZURESACS, SA_CONTAINER)