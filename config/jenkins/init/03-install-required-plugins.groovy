import jenkins.model.*
import java.util.logging.Level
import java.util.logging.Logger

final Logger logger = Logger.getLogger("Install-Plugins")

def instance = Jenkins.getInstance()

def pluginList = [
    "instance-identity",
]

def pm = instance.getPluginManager()
def uc = instance.getUpdateCenter()

logger.log(Level.INFO, "Starting plugin installation")

// Update the update center site data
uc.updateAllSites()

pluginList.each { pluginName ->
    def plugin = pm.getPlugin(pluginName)
    if (plugin == null) {
        logger.log(Level.INFO, "Installing ${pluginName}")
        def installFuture = uc.getPlugin(pluginName).deploy(true)
        
        while(!installFuture.isDone()) {
            logger.log(Level.INFO, "Waiting for plugin installation: ${pluginName}")
            sleep(3000)
        }
        
        if (installFuture.isDone()) {
            logger.log(Level.INFO, "Plugin ${pluginName} installed successfully")
        } else {
            logger.log(Level.WARNING, "Plugin ${pluginName} installation failed")
        }
    } else {
        logger.log(Level.INFO, "Plugin ${pluginName} already installed")
    }
}

// Save current instance to persist changes
instance.save()
logger.log(Level.INFO, "Plugin installation completed")