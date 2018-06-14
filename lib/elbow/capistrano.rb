require 'aws-sdk'
require 'net/dns'
require 'capistrano/dsl'

  include Capistrano::DSL

  def elastic_load_balancer(name, *args)
    find_instances(name).each do |instance|
      hostname = instance.public_dns_name.empty? ? instance.private_ip_address : instance.public_dns_name
      server(hostname, *args)
    end
  end

  def elastic_load_balancerV2(name, *args)
    find_instancesV2(name).each do |instance|
      hostname = instance.public_dns_name.empty? ? instance.private_ip_address : instance.public_dns_name
      server(hostname, *args)
    end
  end

  def elastic_load_balancer_single_instance(name, *args)
    instance = find_instances(name).first
    hostname = instance.public_dns_name.empty? ? instance.private_ip_address : instance.public_dns_name
    server(hostname, *args)
  end

  def elastic_load_balancerV2_single_instance(name, *args)
    instance = find_instancesV2(name).first
    hostname = instance.public_dns_name.empty? ? instance.private_ip_address : instance.public_dns_name
    server(hostname, *args)
  end

  def find_instances(name)
    cname = find_cname(name)
    aws_region= fetch(:aws_region, 'us-east-1')
    credentials = Aws::Credentials.new(fetch(:aws_access_key_id), fetch(:aws_secret_access_key))

    elb = Aws::ElasticLoadBalancing::Client.new(region: aws_region, credentials: credentials)
    load_balancer = elb.describe_load_balancers.load_balancer_descriptions.find {|elb| elb.dns_name.downcase == cname.downcase }
    raise "EC2 Load Balancer not found for #{name} in region #{aws_region}" if load_balancer.nil?

    instance_ids = load_balancer.instances.map(&:instance_id)
    ec2 = Aws::EC2::Client.new(region: aws_region, credentials: credentials)
    ec2.describe_instances(instance_ids: instance_ids).reservations.map(&:instances).flatten
  end

  def find_instancesV2(name)
    cname = find_cname(name)
    aws_region= fetch(:aws_region, 'us-east-1')
    credentials = Aws::Credentials.new(fetch(:aws_access_key_id), fetch(:aws_secret_access_key))

    elb = Aws::ElasticLoadBalancingV2::Client.new(region: aws_region, credentials: credentials)
    load_balancer = elb.describe_load_balancers.load_balancers.find {|elb| elb.dns_name.downcase == cname.downcase }
    raise "EC2 Load Balancer not found for #{name} in region #{aws_region}" if load_balancer.nil?
    target_group = elb.describe_target_groups.target_groups.find {|tg| tg.load_balancer_arns.include?(load_balancer.load_balancer_arn)}
    raise "EC2 Target Group not found for #{name} in region #{aws_region}" if target_group.nil?

    instance_ids = elb.describe_target_health({target_group_arn: target_group.target_group_arn}).target_health_descriptions.map{|desc| desc.target.id}
    ec2 = Aws::EC2::Client.new(region: aws_region, credentials: credentials)
    ec2.describe_instances(instance_ids: instance_ids).reservations.map(&:instances).flatten
  end

  def find_cname(name)
    packet = Net::DNS::Resolver.start(name)
    all_cnames= packet.answer.reject { |p| !p.instance_of? Net::DNS::RR::CNAME }
    all_cnames.find { |c| c.name == "#{name}."}.cname[0..-2]
  end

