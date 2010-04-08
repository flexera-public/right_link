powershell 'echo_from_powershell_script' do
  source_text = 'write-output "message from powershell script"'
  source source_text
end



