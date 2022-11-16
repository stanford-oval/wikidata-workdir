import os
import time
import argparse
import openai
from openai import cli

openai.api_key = os.environ['OPENAI_API_KEY']
openai.api_base = 'https://ovalopenairesource.openai.azure.com/'
openai.api_type = 'azure'
openai.api_version = '2022-06-01-preview' 

def file_status(file_id):
    status = openai.File.retrieve(file_id)["status"]
    while status not in ['success', 'failed']:
        time.sleep(1)
        openai.File.retrieve(file_id)["status"]
    print(openai.File.retrieve(file_id))
    return status

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--train', type=str, required=True, help='Path to the training data')
    parser.add_argument('--validate', type=str, required=True, help="Path to the validation data")
    parser.add_argument('--model', type=str, help='The GPT-3 base model to use')

    # training hparams
    parser.add_argument('--epochs', type=int, default=1, required=False, help='Number of epochs')
    parser.add_argument('--lr', type=float, default=0.1, required=False, help="Learning rate multiplier")
    parser.add_argument('--suffix', type=str, required=True, help="The suffix of the name for the model to be trained")

    args = parser.parse_args()
    print(openai.api_key)
    print(args)

    train_id = cli.FineTune._get_or_upload(args.train)
    validate_id = cli.FineTune._get_or_upload(args.validate)

    print(file_status(train_id))
    print(file_status(validate_id))
    response = openai.FineTune.create(training_file=train_id,
                                        validation_file=validate_id,
                                        model=args.model,
                                        n_epochs=args.epochs,
                                        learning_rate_multiplier=args.lr,
                                        suffix=args.suffix)
    print(response)