Pod::Spec.new do |s|
  s.name         = "Backand-iOS-SDK"
  s.module_name  = 'Backand'
  s.version      = "0.1.0"
  s.summary      = "A Backand SDK for iOS."
  s.description  = <<-DESC
                  A simple SDK for interacting with the Backand REST API for iOS, written in Swift.
                   DESC
  s.homepage     = "https://github.com/jakelawson1/Backand-iOS-SDK"
  s.license      = { :type => 'MIT', :file => 'LICENSE' }
  s.author       = { "Jake Lawson" => "jakelawson1@hotmail.com" }
  s.source       = { :git => "https://github.com/jakelawson1/Backand-iOS-SDK.git", :tag => "#{s.version}" }

  s.platform     = :ios, "8.0"

  s.source_files = 'Source/**'
  s.framework    = "Foundation"
  s.dependency "Alamofire", "~> 3.4"
  s.dependency 'SwiftKeychainWrapper'
end
