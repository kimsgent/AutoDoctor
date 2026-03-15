$python = "C:\Users\$env:USERNAME\AppData\Local\Programs\Python\Python312\python.exe"
Set-Location "C:\ProgramData\AutoDoctor\server\api"

& $python autodoctor_service.py --startup auto install
& $python autodoctor_service.py start
