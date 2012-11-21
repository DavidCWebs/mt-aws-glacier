mt-aws-glacier
==============
Perl Multithreaded multipart sync to Amazon AWS Glacier service.

## Intro

Amazon AWS Glacier is an archive/backup service with very low storage price. However with some caveats in usage and archive retrieval prices.
[Read more about Amazon AWS Glacier](http://aws.amazon.com/glacier/) 

mt-aws-glacier is a client application	 for Glacier.

## Version

* Version 0.75 beta

## Features

* Does not use any existing AWS library, so can be flexible in implementing advanced features
* Glacier Multipart upload
* Multithreaded upload
* Multipart+Multithreaded upload
* Multithreaded retrieval, deletion and download
* Tracking of all uploaded files with a local journal file (opened for write in append mode only)
* Checking integrity of local files using journal
* Ability to limit number of archives to retrieve

## Coming-soon features

* Multipart download (using HTTP Range header)
* Ability to limit amount of archives to retrieve, by size, or by traffic/hour
* Use journal file as flock() mutex
* Checking integrity of remote files
* Upload from STDIN
* Some integration with external world, ability to read SNS topics
* Simplified distribution for Debian/RedHat
* Split code to re-usable modules, publish on CPAN (Currently there are great existing Glacier modules on CPAN - see Net::Amazon::Glacier by Tim Nordenfur https://metacpan.org/module/Net::Amazon::Glacier ) 
* Create/Delete vault function

## Planed next version features

* Amazon S3 support

## Important bugs/missed features

* Zero length files are ignored
* chunk size hardcoded as 2MB
* Only multipart upload implemented, no plain upload
* Retrieval works as proof-of-concept, so you can't initiate retrieve job twice (until previous job is completed)
* No way to specify SNS topic 
* HTTP only, no way to configure HTTPS yet (however it works fine in HTTPS mode)
* Internal refactoring needed, no comments in source yet, unit tests not published
* Journal file required to restore backup. To be fixed. Will store file metainformation in archive description.

## Production ready

* Not recomended to use in production until first "Release" version. Currently Beta.

## Installation/System requirements

Script is made for Linux OS. Tested under Ubuntu and Debian. Should work under other Linux distributions. Not tested under Mac OS.
Should NOT work under Windows. 

Install the following CPAN modules:

* **LWP::UserAgent** (or Debian package **libwww-perl**)
* **JSON::XS** (or Debian package **libjson-xs-perl**)
* **LWP::Protocol::https** (or Debian package **liblwp-protocol-https-perl**) ( *is only needed in case you are going to use HTTPS* )
* **URI** (or Debian package **liburi-perl**)
		
Install using *cpan*:

				cpan -i LWP::UserAgent JSON::XS URI  LWP::Protocol::https 

Install using *apt-get*:
				
				apt-get install libwww-perl libjson-xs-perl liburi-perl  liblwp-protocol-https-perl

## Warnings ( *MUST READ* )

* When playing with Glacier make sure you will be able to delete all your archives, it's impossible to delete archive
or non-empty vault in amazon console now. Also make sure you have read _all_ AWS Glacier pricing/faq.

* Read their pricing FAQ again, really. Beware of retrieval fee.

* *Backup your local journal file*. Currently it's impossible to correctly restore backup without journal file. ( *Remote metadata storage will be implemented soon* )

* With low "partsize" option you pay a bit more (Amazon charges for each upload request)

* With high partsize*concurrency there is a risk of getting network timeouts HTTP 408/500 or even signature expiration errors.

* Memory usage (for 'sync') formula is ~ min(NUMBER_OF_FILES_TO_SYNC, max-number-of-files) + partsize*concurrency

## Usage
 
1. Create a directory containing files to backup. Example `/data/backup`
2. Create config file, say, glacier.cfg

				key=YOURKEY                                                                                                                                                                                                                                                      
				secret=YOURSECRET                                                                                                                                                                                                                               
				region=us-east-1 #eu-west-1, us-east-1 etc

3. Create a vault in specified region, using Amazon Console (`myvault`)
4. Choose a filename for the Journal, for example, `journal.log`
5. Sync your files

				./mtglacier.pl sync --config=glacier.cfg --from-dir /data/backup --to-vault=myvault --journal=journal.log --concurrency=3
				
6. Add more files and sync again
7. Check that your local files not modified since last sync

				./mtglacier.pl check-local-hash --config=glacier.cfg --from-dir /data/backup --to-vault=myvault -journal=journal.log
    
8. Delete some files from your backup location
9. Initiate archive restore job on Amazon side

				./mtglacier.pl restore --config=glacier.cfg --from-dir /data/backup --to-vault=myvault -journal=journal.log --max-number-of-files=10
    
10. Wait 4+ hours
11. Download restored files back to backup location

				./mtglacier.pl restore-completed --config=glacier.cfg --from-dir /data/backup --to-vault=myvault -journal=journal.log
    
12. Delete all your files from vault

				./mtglacier.pl purge-vault --config=glacier.cfg --from-dir /data/backup --to-vault=myvault -journal=journal.log

## Additional command line options

1. "concurrency" (with 'sync' command) - number of parallel upload streams to run. (default 4)

				--concurrency=4
				
2. "partsize" (with 'sync' command) - size of file chunk to upload at once, in Megabytes. (default 16)

				--partsize=16
				
3. "max-number-of-files" (with 'sync' or 'restore' commands) - limit number of files to sync/restore. Program will finish when reach this limit.

				--max-number-of-files=100

## Test/Play with it

1. create empty dir MYDIR
2. Set vault name inside `cycletest.sh`
3. Run

		./cycletest.sh init MYDIR
		./cycletest.sh retrieve MYDIR
		./cycletest.sh restore MYDIR

OR

		./cycletest.sh init MYDIR
		./cycletest.sh purge MYDIR
		
		
## Minimum AWS permissions

something like that

				{
  				"Statement": [
    				{
      				"Effect": "Allow",
      				"Resource":["arn:aws:glacier:eu-west-1:XXXXXXXXXXXX:vaults/test1",
		  				"arn:aws:glacier:us-east-1:XXXXXXXXXXXX:vaults/test1",
		  				"arn:aws:glacier:eu-west-1:XXXXXXXXXXXX:vaults/test2",
		  				"arn:aws:glacier:eu-west-1:XXXXXXXXXXXX:vaults/test3"],
      				"Action":["glacier:UploadArchive",
                				"glacier:InitiateMultipartUpload",
								"glacier:UploadMultipartPart",
                				"glacier:UploadPart",
                				"glacier:DeleteArchive",
								"glacier:ListParts",
								"glacier:InitiateJob",
								"glacier:ListJobs",
								"glacier:GetJobOutput",
								"glacier:ListMultipartUploads",
								"glacier:CompleteMultipartUpload"] 
    				}
  				]
				}


[![tracking pixel](https://mt-aws.com/mt-aws-glacier-transp.gif "t1")](http://mt-aws.com/)
 
