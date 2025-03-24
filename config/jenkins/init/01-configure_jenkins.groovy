import jenkins.model.*
import hudson.security.*
import jenkins.security.s2m.AdminWhitelistRule
import jenkins.install.InstallState
import hudson.security.csrf.DefaultCrumbIssuer

// Get Jenkins instance
def instance = Jenkins.getInstance()

// Skip setup wizard and set Jenkins to RUNNING state
instance.setInstallState(InstallState.INITIAL_SETUP_COMPLETED)

// Set Jenkins URL prefix and root URL
def url = System.getenv("HOST_IP") ?: "localhost"
def jenkinsUrl = "https://${url}/jenkins/"
instance.setRootUrl(jenkinsUrl)
instance.setResourceRootUrl(jenkinsUrl)

// Set agent port
instance.setSlaveAgentPort(50000)

// Configure security realm with admin user
def adminUser = System.getenv("JENKINS_ADMIN_USER") ?: "admin"
def adminPass = System.getenv("JENKINS_ADMIN_TOKEN") ?: "securepassword"

def hudsonRealm = new HudsonPrivateSecurityRealm(false)
hudsonRealm.createAccount(adminUser, adminPass)
instance.setSecurityRealm(hudsonRealm)

// Force authentication (restrict access to logged-in users only)
def strategy = new GlobalMatrixAuthorizationStrategy()
strategy.add(Jenkins.ADMINISTER, adminUser)  // Admin access
strategy.add(Jenkins.READ, adminUser)       // Ensure read access
strategy.add(Jenkins.READ, "authenticated") // Allow only authenticated users
instance.setAuthorizationStrategy(strategy)

// Configure CSRF protection with proxy compatibility
instance.setCrumbIssuer(new DefaultCrumbIssuer(true))

// Enable remoting for agents
Jenkins.instance.getInjector().getInstance(AdminWhitelistRule.class).setMasterKillSwitch(false)

// Save configuration
instance.save()

println "Jenkins configured successfully! Admin user: ${adminUser}"
