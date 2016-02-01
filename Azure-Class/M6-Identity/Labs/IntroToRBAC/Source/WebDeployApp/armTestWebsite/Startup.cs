using Microsoft.Owin;
using Owin;

[assembly: OwinStartupAttribute(typeof(armTestWebsite.Startup))]
namespace armTestWebsite
{
    public partial class Startup {
        public void Configuration(IAppBuilder app) {
            ConfigureAuth(app);
        }
    }
}
