Pod::Spec.new do |s|
  s.name             = 'kirz_blurry_image_detector'
  s.version          = '1.0.4'
  s.summary          = 'Blurry detector plugin'
  s.description      = 'Metal/MPS Laplacian variance'
  s.homepage         = 'https://github.com/zaikir'
  s.license          = { :type => 'MIT' }
  s.author           = { 'Zaikir' => 'https://github.com/zaikir' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency       'Flutter'
  s.platform         = :ios, '12.0'
  s.frameworks       = 'Metal', 'MetalKit', 'MetalPerformanceShaders', 'Accelerate', 'Photos'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
end
