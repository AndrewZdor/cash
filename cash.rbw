require 'Win32Serial.so'
require "yaml"
require 'vr/vrcontrol'  
require 'vr/vrtray'  
#require 'fileutils'
require "ftools"

module CashHandler  
  include VRTrayiconFeasible  
  include VRMenuUseable  
  LoadIcon = Win32API.new("user32","LoadIcon","II","I")  
  QUESTION_ICON= LoadIcon.call(0,32514)  
  EXCLAMATION_ICON = LoadIcon.call(0,32515)  
  
  CONFIG = YAML.load_file("config.yaml")
      
  # Определение Меню
  def construct  
    self.caption="Cash"  
    @traymenu = newPopupMenu  
   
    @menu_connect = @traymenu.append "Подключение ЭККР", "connect"
    @menu_disconnect = @traymenu.append "Отключение ЭККР", "disconnect", VRMenuItem::GRAYED 
      @menu_separator1 = @traymenu.append "sep", "_vrmenusep", 0x800
    @menu_exit = @traymenu.append "Выход", "exit"
    
    create_trayicon(QUESTION_ICON,"Maria-301 MTM: Отключен",0)
    connect_clicked if CONFIG["ConnectOnStartup"]
    #showPopup @traymenu if CONFIG["ConnectOnStartup"]
    
  end 
        
  def cash_actions_set_state(state)
    @menu_connect.state=(state-1).abs if @menu_connect
    @menu_disconnect.state=state if @menu_disconnect   
  end
  
  # Запускает проверку файла в отдельном потоке
  def check_file 
    @do_check = true
    #puts CONFIG["InputFile"]
        
    thread = Thread.new do
      while @do_check do
        #Ожидаем появления файла с коммандами
        if File.file? CONFIG["InputFile"]
          output = ""
          # Обрабатываем все комманды внутри файла
          input_file = File.open(CONFIG["InputFile"]).each do |x|
            output += "\r\n" if output != ""
            len = x.length + 1
            input = 253.chr + x + len.chr + 254.chr
            @port.write(input)
            out = @port.read(255)
            output += out
            # ждем пока касса не скажет что она готова
            while not out.include? "READY"
              sleep CONFIG["BusyTimeOut"]        
              out = @port.read(255)
              output += out   
            end            
          end
        
          #backup_file(CONFIG["InputFile"], true)
          input_file.close
          File.delete(CONFIG["InputFile"])
          open(CONFIG["OutputFile"], "w") { |o| o.puts output }                    
        else
          sleep CONFIG["TimeOut"]        
        end
      end        
    end    
  end
  
  def backup_file(filename, move=false)
    new_filename = nil
	
	if File.exists? filename then
      new_filename = File.versioned_filename(filename, '.000')
      File.send(move ? :move : :copy, filename, new_filename)
    end
 	
 	return new_filename    
  end
       
  # соединение с кассой
  def connect_clicked    
    
    @port = Win32Serial.new
    
    ret = @port.open(CONFIG["ComPort"])
    #puts 'opens the specified comport. (returns nil on error). return = ' + ret.to_s
    
    ret = @port.config(CONFIG["BaudRate"], 8, Win32Serial::EVENPARITY, Win32Serial::TWOSTOPBITS)
    #puts 'configures the port to the appropriate settings. (returns nil on error). return = ' + ret.to_s
     
    # timeouts ОБЯЗАТЕЛЬНО - БЕЗ ЭТОГО НЕ РАБОТАЕТ !!!
    # ReadInterval by default should be = 100
    @port.timeouts(CONFIG["ReadInterval"], 0, 0, 0, 0) 
    
    sleep 1.5
    @port.write("U")
    sleep(0.002)
    @port.write("U")
    
    output = @port.read(255)  
    #puts output
    
    input = 253.chr + "UPAS" + CONFIG["Password"].to_s + CONFIG["User"] + 20.chr + 254.chr    
    @port.write(input)
    output = @port.read(255)
    #puts output
    
    modify_trayicon(EXCLAMATION_ICON,"Maria-301 MTM: Подключен",0)  
    cash_actions_set_state(0)
    #puts "Connected !" 
    
    check_file
    #puts "Check file started !"     
    
  end  
  
  # отсоединение от кассы
  def disconnect_clicked  
    if @port then  
      @port.close
      
      modify_trayicon(QUESTION_ICON,"Maria-301 MTM: Отключен",0)  
      cash_actions_set_state(VRMenuItem::GRAYED)
      @do_check = false
      #puts "Disconnected !"      
     end    
  end  
 
  def self_traylbuttondown(iconid)  
  end  
  
  def self_trayrbuttonup(iconid)  
    showPopup @traymenu  
  end  
  
  def exit_clicked 
    disconnect_clicked
    delete_trayicon(0)  
    #puts "Exit !"  
    exit    
  end  
end  

frm = VRLocalScreen.newform  
frm.extend CashHandler  
frm.create  
VRLocalScreen.messageloop 
