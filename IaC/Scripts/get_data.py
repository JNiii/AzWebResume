import json
import sys

from azure.cosmos import CosmosClient

def get_data(URI, KEY, DB, CONTAINER):
    client = CosmosClient(URI, credential=KEY)
    database = client.get_database_client(DB)
    container = database.get_container_client(CONTAINER)
    item = container.read_item(item="1", partition_key="1")
    with open('./Scripts/data.json', 'w+') as outfile:
        new_item = {
            'id': item['id'],
            'count': item['count']
        }
        json.dump(new_item, outfile)
        outfile.close()


if __name__== "__main__":
    URI = sys.argv[1]
    KEY = sys.argv[2]
    DB = sys.argv[3]
    CONTAINER = sys.argv[4]
    get_data(URI, KEY, DB, CONTAINER)

#use 'python get_data.py <URI> <KEY> <DB name> <Container name>' when calling