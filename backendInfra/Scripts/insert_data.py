import json
import os
import sys

from azure.cosmos import CosmosClient
from azure.storage.blob import BlobServiceClient



def insert_data(URI, KEY, DB, CONTAINERDB, AZURESACS, SA_CONTAINER):

    client = CosmosClient(URI, credential=KEY)
    database = client.get_database_client(DB)
    containerdb = database.get_container_client(CONTAINERDB)
    blob_service_client = BlobServiceClient.from_connection_string(AZURESACS)
    sa_container_client = blob_service_client.get_container_client(SA_CONTAINER)
    sa_blob_client = sa_container_client.get_blob_client("data.json")
    with open('./Scripts/data.json', 'wb') as f:
        data = sa_blob_client.download_blob()
        data.readinto(f) 

    infile = open('./Scripts/data.json', 'r')

    data= json.load(infile)
    containerdb.create_item(body=data)
    infile.close()
    if os.path.exists('./Scripts/data.json'):
        os.remove('./Scripts/data.json')

if __name__== "__main__":

    URI = sys.argv[1]
    KEY = sys.argv[2]
    DB = sys.argv[3]
    CONTAINERDB = sys.argv[4]
    AZURESACS = sys.argv[5]
    SA_CONTAINER = sys.argv[6]
    insert_data(URI, KEY, DB, CONTAINERDB, AZURESACS, SA_CONTAINER)

