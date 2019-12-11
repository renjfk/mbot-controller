# Uncomment the next line to define a global platform for your project
# platform :ios, '9.0'

target 'MBot' do
  # Comment the next line if you don't want to use dynamic frameworks
  use_frameworks!

  # Pods for MBot
  pod 'BlueCapKit', '~> 0.7.0'
  pod 'Alertift', '~> 4.1'
  pod 'FontAwesome.swift'

  post_install do |installer|
    installer.pods_project.targets.each do |target|
      target.build_configurations.each do |config|
        if config.name == 'Debug'
          config.build_settings['OTHER_SWIFT_FLAGS'] ||= ['$(inherited)', '-D DEBUG']
        end
      end
    end
  end
end
