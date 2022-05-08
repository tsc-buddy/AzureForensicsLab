# AzureForensicsLab

## Scene Setting

This repo contains Azure Bicep Source code to deploy a computer forensics chain of custody solution based on the following article.

[Microsoft Docs - Computer Forensics Chain of custody](https://docs.microsoft.com/en-us/azure/architecture/example-scenario/forensics/)

The Azure Bicep code that you will find in this repository will deploy all the Azure infrastructure components, including all automation account runbooks required to build both Hybrid workers and execute the workflow activities of the chain of customer concept as illustrated below within the SoC Subscription.

![CoCArchitecture](https://docs.microsoft.com/en-us/azure/architecture/example-scenario/forensics/media/chain-of-custody.png)

## Deployment Guide

This guide assumes that you already have Azure Powershell installed and ready for use on your local machine or the machine you wish to run the deployment from. For more information on Azure PS installation see here: [Install Azure PS](https://docs.microsoft.com/en-us/powershell/azure/install-az-ps?msclkid=22b33880cf1b11eca24aab5d7e475a88&view=azps-7.5.0#installation)

1. Pull down the contents on this repository, all the source code for infrastructure and chain of custody automation resides in here.
2. Open up a PS terminal and CD to the .\bicep directory where the main.bicep file resides.
3. Login to Azure with login-azAccount. Ensure that once you are logged in, you are in the correct subscription context.
4. 
