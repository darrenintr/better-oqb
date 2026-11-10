Pod::Spec.new do |s|
  s.name = 'oqb_pencil_bridge'
  s.version = '0.1.0'
  s.summary = 'Apple Pencil tool interactions'
  s.description = 'Double tap and squeeze events for Better OQB.'
  s.homepage = 'https://github.com/darrenintr/better-oqb'
  s.license = { :type => 'MIT' }
  s.author = { 'Better OQB' => 'darrenintr@users.noreply.github.com' }
  s.source = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '13.0'
  s.swift_version = '5.0'
end
