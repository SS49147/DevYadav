import jenkins.model.Jenkins
import jenkins.install.InstallState
import hudson.security.HudsonPrivateSecurityRealm
import hudson.security.FullControlOnceLoggedInAuthorizationStrategy
import jenkins.model.JenkinsLocationConfiguration

def instance = Jenkins.get()
def realm = new HudsonPrivateSecurityRealm(false)
realm.createAccount('admin', new File(System.getenv('JENKINS_ADMIN_PASSWORD_FILE')).text.trim())
instance.setSecurityRealm(realm)
def authorization = new FullControlOnceLoggedInAuthorizationStrategy()
authorization.setAllowAnonymousRead(false)
instance.setAuthorizationStrategy(authorization)
instance.setNumExecutors(1)
instance.setSlaveAgentPort(-1)
instance.setInstallState(InstallState.INITIAL_SETUP_COMPLETED)
JenkinsLocationConfiguration.get().setUrl('http://127.0.0.1:18009/')
instance.save()
