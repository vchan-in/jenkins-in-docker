import jenkins.model.*
import hudson.security.*
import jenkins.security.s2m.AdminWhitelistRule
import jenkins.install.InstallState
import hudson.security.csrf.DefaultCrumbIssuer

// Get Jenkins instance
def instance = Jenkins.getInstance()

// Skip setup wizard and set Jenkins to RUNNING state
instance.setInstallState(InstallState.INITIAL_SETUP_COMPLETED)

// Configure the Jenkins Location
def jlc = JenkinsLocationConfiguration.get()
def url = System.getenv("HOST_IP") ?: "localhost"
jlc.setUrl("https://${url}/jenkins/")
jlc.save()

// Set agent port
instance.setSlaveAgentPort(50000)

// Configure CSRF protection with proxy compatibility
instance.setCrumbIssuer(new DefaultCrumbIssuer(true))

// Save configuration
instance.save()

println "Jenkins URL configured successfully."
