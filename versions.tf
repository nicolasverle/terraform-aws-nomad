terraform {
    backend "s3" {
        bucket = "nomad-states" # <==== your bucket name here
        region = "eu-west-3" # <==== your aws region here
        key = "terraform"
    }
}