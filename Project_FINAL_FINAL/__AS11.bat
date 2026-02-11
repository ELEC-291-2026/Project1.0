@echo off
C:
cd "\Users\pamel\OneDrive\Desktop\School\CrossIDE\06_Project_1\Current_Project\"
if exist De10-lite_project.lst del De10-lite_project.lst
if exist De10-lite_project.s19 del De10-lite_project.s19
if exist __err.txt del __err.txt
"C:\Program Files\CrossIDE\Call51\Bin\a51.exe"  De10-lite_project.asm > __err.txt
"C:\Program Files\CrossIDE\Call51\Bin\a51.exe"  De10-lite_project.asm -l > De10-lite_project.lst
if not exist s2mif.exe goto done
if exist De10-lite_project.s19 s2mif De10-lite_project.s19 De10-lite_project.mif > nul
:done
