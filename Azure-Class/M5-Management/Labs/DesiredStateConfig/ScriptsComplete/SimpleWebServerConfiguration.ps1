# This is the structural configuration file that creates the structure and components that will be on the 
# server being setup
Configuration InstallWebServer
{
    # We will use a parameter to determine where our source code is located on our
    # local disk
    param (

        [Parameter(Mandatory=$True,Position=1)]
        [string]$websiteSourceLocation

      )
   Import-DscResource -Module xWebAdministration

    # It is possible that in our ConfigurationData.psd1 file we could specify
    # multiple nodes of various names. In this case, if one or more of these servers
    # we named 'WebServer' it would fall into this node detail area
    node $AllNodes.Where{$_.Role -eq "WebServer"}.NodeName
    {

   
         LocalConfigurationManager
        {   
                ConfigurationID ="43d4995d-3199-4e0d-aef5-d52d3b681ac4";      
                RebootNodeIfNeeded = $true;
        }     

        # Install the IIS role  
        WindowsFeature IIS  
        {  
            Ensure          = "Present"  
            Name            = "Web-Server"  
        }  
        
        # Install the ASP .NET 4.5 role  
        WindowsFeature AspNet45  
        {  
            Ensure          = "Present"  
            Name            = "Web-Asp-Net45"  
        }  
    
        # Stop the default website  
        xWebsite DefaultSite   
        {  
            Ensure          = "Present"  
            Name            = "Default Web Site"  
            State           = "Stopped"  
            PhysicalPath    = "C:\inetpub\wwwroot"  
            DependsOn       = "[WindowsFeature]IIS"  
        }  
  
        # Copy the website content  
        File WebContent  
        {  
            Ensure          = "Present"  
            SourcePath      = $websiteSourceLocation 
            DestinationPath = "C:\inetpub\OurBakery" 
            Recurse         = $true  
            Type            = "Directory"  
            DependsOn       = "[WindowsFeature]AspNet45"  
        }   

        # Create a new website  
        xWebsite BakeryWebSite   
        {  
            Ensure          = "Present"  
            Name            = "OurBakery" 
            State           = "Started"  
            PhysicalPath    = "C:\inetpub\OurBakery"  
            DependsOn       = "[File]WebContent"  
        }
    }
}