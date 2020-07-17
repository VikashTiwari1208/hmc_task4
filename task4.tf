// aws + terraform //

// providing credentials in form of profile for better securities//

provider "aws"{
 
 region = "ap-south-1"
 
 profile = "vik_iam1"

 
}


// creating key

resource  "tls_private_key" "mykey" {
  algorithm   = "RSA"
}

resource "aws_key_pair" "generated_key"{
  
  key_name = "mykey"

  public_key = "${tls_private_key.mykey.public_key_openssh}"

  depends_on = [

      tls_private_key.mykey
  ]

}

resource "local_file" "key-file" {

    content= "${tls_private_key.mykey.private_key_pem}"
    filename = "mykey.pem"
    depends_on = [

        tls_private_key.mykey

    ]
}

// now creating vpc //

resource "aws_vpc" "main" {

  cidr_block       = "192.168.0.0/16"
  
  instance_tenancy = "default"

  enable_dns_hostnames = "true"

  assign_generated_ipv6_cidr_block = "true"
  
  tags = {
    Name = "my-vpc"
  }
}

//creating security groups //

resource "aws_security_group" "my_rules" {

     depends_on = [aws_vpc.main]

  name        = "public_sg"
  description = "allowing ssh and http"
  vpc_id      = "${aws_vpc.main.id}"

  ingress {
    description = "allowing ssh"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

ingress {
    description = "allowing http"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "allowing mysql database"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

 ingress {
    description = "allow ICMP"
    from_port = -1
    to_port = -1
    protocol = "ICMP"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "allowing_selected ssh http icmp protocols"
  }
 
}

//security rules for private subnet for mysql

resource "aws_security_group" "private_rules" {

  depends_on = [aws_vpc.main]

 name = "private_sg"

 description = "allow mysql sg"

 vpc_id = "${aws_vpc.main.id}"

 ingress {
   description = "allow_MYSQL/Aurora"

   from_port = 3306

   to_port = 3306

   protocol = "tcp"

   security_groups = ["${aws_security_group.my_rules.id}"]
   
 }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks =  ["0.0.0.0/0"]
  }

}
//create security rules for bashion host

resource "aws_security_group" "bashion_host" {
  depends_on = [aws_vpc.main]

  name = "rules-for-bashion-host"

  description= "allowing rule to ssh login to bashion host"
  
  vpc_id= "${aws_vpc.main.id}"

  ingress {
    description = "allow ssh"
    from_port = 22
    to_port  = 22
    protocol = "tcp"
    cidr_blocks =  ["0.0.0.0/0"]
  }
   ingress {
    description = "allow ping"
    from_port = -1
    to_port  = -1
    protocol = "icmp"
    cidr_blocks =  ["0.0.0.0/0"]
  }
   egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks =  ["0.0.0.0/0"]
  }
}

// creating security rules for ssh to my sql via basion host server

resource "aws_security_group" "sg" {

  depends_on = [aws_vpc.main,aws_security_group.bashion_host]

name = "allowing_bashion_host_to-ssh"

description = "bashion_host_allow_ssh"

vpc_id = "${aws_vpc.main.id}"

ingress {
description = "allow ssh"
from_port = 22
to_port =  22
protocol = "tcp"
security_groups =["${aws_security_group.bashion_host.id}"]
}
ingress {
description = "allow pinging"
from_port = -1
to_port =  -1
protocol = "icmp"
security_groups =["${aws_security_group.bashion_host.id}"]
}
egress {
 from_port= 0
 to_port= 0
 protocol = "-1"
 cidr_blocks= ["0.0.0.0/0"]
}

}


// launching subnets //

//creating public subnet//
resource "aws_subnet" "subnet1" {

depends_on = [aws_vpc.main]

vpc_id= "${aws_vpc.main.id}"

cidr_block = "192.168.0.0/24"

availability_zone = "ap-south-1a"

tags = {

    Name = "public_subnet"
}
}


// creating private subnet

resource "aws_subnet" "subnet2" {

    
depends_on = [aws_vpc.main]

vpc_id= "${aws_vpc.main.id}"

cidr_block = "192.168.1.0/24"

availability_zone = "ap-south-1b"

tags = {

    Name = "private_subnet"
}
}

//code for internet gateway //

resource "aws_internet_gateway" "ig" {

    
depends_on = [aws_vpc.main]

vpc_id = "${aws_vpc.main.id}"

  tags = {
    Name = "my gateway"
  }

}

//code for updating routing table

resource "aws_route_table" "routing" {

    
depends_on = [ aws_vpc.main, aws_internet_gateway.ig ]

     vpc_id = "${aws_vpc.main.id}"

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = "${aws_internet_gateway.ig.id}"
  }
  tags = {
   
   Name = "route-table-1"
  }
}

//resource for aws epi
resource "aws_eip" "eip"{

depends_on = [aws_vpc.main,aws_internet_gateway.ig]

vpc = true
}
//creating nat gateway

resource "aws_nat_gateway" "natgw"{

depends_on = [aws_vpc.main,aws_eip.eip,aws_subnet.subnet1]
allocation_id = "${aws_eip.eip.id}"

subnet_id= "${aws_subnet.subnet1.id}"

tags = {
Name = "NAT GATEWAY"
}
}

resource "aws_route_table" "routing2" {

vpc_id = "${aws_vpc.main.id}"

route {
cidr_block = "0.0.0.0/0"

nat_gateway_id = "${aws_nat_gateway.natgw.id}"
}
tags = {
  Name = "Route-table-2"
}
}
resource "aws_route_table_association" "nat_route_association" {

depends_on = [aws_route_table.routing2]

subnet_id = "${aws_subnet.subnet1.id}"

route_table_id = "${aws_route_table.routing2.id}"
}


resource "aws_route_table_association" "tosubnet1" {

    depends_on = [aws_route_table.routing]

subnet_id = "${aws_subnet.subnet1.id}"

route_table_id = "${aws_route_table.routing.id}"
}

resource "aws_instance" "wordpress" {

    depends_on = [tls_private_key.mykey,aws_vpc.main, aws_security_group.my_rules,aws_internet_gateway.ig ,aws_route_table.routing]
 
 ami = "ami-08706cb5f68222d09"

 instance_type = "t2.micro"

 key_name = "${aws_key_pair.generated_key.key_name}"

 vpc_security_group_ids = [aws_security_group.my_rules.id]

 associate_public_ip_address = "true"

subnet_id = "${aws_subnet.subnet1.id}"
tags = {
  Name = "wordpress Server"
}

}

 resource "aws_instance" "my-sql" {

  depends_on = [tls_private_key.mykey,aws_vpc.main, aws_security_group.my_rules,aws_internet_gateway.ig ,aws_route_table.routing,aws_route_table.routing2]
 
 ami = "ami-08706cb5f68222d09"

 instance_type = "t2.micro"

 key_name = "${aws_key_pair.generated_key.key_name}"

 vpc_security_group_ids = [aws_security_group.private_rules.id,aws_security_group.sg.id]

 associate_public_ip_address = "false"

subnet_id = "${aws_subnet.subnet2.id}"

tags = {
  Name = "Mysql-instance"
}
}

resource "aws_instance" "bashion_host" {

  depends_on = [tls_private_key.mykey,aws_vpc.main, aws_security_group.my_rules,aws_internet_gateway.ig ,aws_route_table.routing,aws_route_table.routing2]

  ami = "ami-0732b62d310b80e97"

instance_type = "t2.micro"

key_name = "${aws_key_pair.generated_key.key_name}"

vpc_security_group_ids =["${aws_security_group.bashion_host.id}"]

subnet_id = "${aws_subnet.subnet1.id}"

associate_public_ip_address = "true"

tags = {
  Name = "Bashion Host-Server"
}

}


                                             //// end  ////