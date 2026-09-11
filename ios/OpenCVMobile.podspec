Pod::Spec.new do |s|
  s.name = 'OpenCVMobile'
  s.version = '4.13.0'
  s.summary = 'Minimal OpenCV framework for the iPhone tracker.'
  s.homepage = 'https://github.com/nihui/opencv-mobile'
  s.license = { :type => 'Apache-2.0' }
  s.author = 'opencv-mobile contributors'
  s.source = {
    :http => 'https://github.com/nihui/opencv-mobile/releases/download/v36/opencv-mobile-4.13.0-ios.zip',
    :sha256 => '631d0be64986b4bdbb8942d5f17c21ae09ec4bc71f2b4e1e2e62c9952a65ab01'
  }
  s.platform = :ios, '13.0'
  s.vendored_frameworks = 'opencv2.framework'
  s.libraries = 'c++', 'z'
  s.frameworks = 'Accelerate', 'Foundation', 'CoreGraphics', 'CoreVideo', 'AVFoundation'
end
