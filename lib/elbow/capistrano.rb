require 'aws-sdk'
require 'net/dns'

Capistrano::Configuration.instance(:must_exist).load do

  def elastic_load_balancer(name, *args)
    load_balancer(name).instances.each do |instance|
      hostname = instance.dns_name || instance.private_ip_address
      server(hostname, *args)
    end
  end

  def elastic_load_balancer_single_instance(name, *args)
    instance = load_balancer(name).instances.first
    hostname = instance.dns_name || instance.private_ip_address
    server(hostname, *args)
  end

  private

  def load_balancer(name)
    packet = Net::DNS::Resolver.start(name)
    all_cnames= packet.answer.reject { |p| !p.instance_of? Net::DNS::RR::CNAME }
    cname = all_cnames.find { |c| c.name == "#{name}."}.cname[0..-2]

    aws_region= fetch(:aws_region, 'us-east-1')
    AWS.config(:access_key_id => fetch(:aws_access_key_id),
               :secret_access_key => fetch(:aws_secret_access_key),
               :ec2_endpoint => "ec2.#{aws_region}.amazonaws.com",
               :elb_endpoint => "elasticloadbalancing.#{aws_region}.amazonaws.com")

    load_balancer = AWS::ELB.new.load_balancers.find { |elb| elb.dns_name.downcase == cname.downcase }
    raise "EC2 Load Balancer not found for #{name} in region #{aws_region}" if load_balancer.nil?
    load_balancer
  end
end

