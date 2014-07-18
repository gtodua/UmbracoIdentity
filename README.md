![ASP.Net Identity for Umbraco](logo.png?raw=true)
===============

Allows for using OWIN &amp; ASP.Net Identity in Umbraco (currently only for the front-end)

Currently this is a test project and will allow the use of ASP.Net Identity and OWIN to work for Umbraco members on your front-end website. Eventually I'll try to add support for back office users too (depending on how possible that is with the current forms-auth tickets). 

Some light reading - This is the majority of articles that had to be read and understood to achieve this:

https://delicious.com/shandem/owin

## Minimum Requirements:

Ideally this should be run against Umbraco 7.1.5 or 6.2.2. I realize these versions are not out (based on today's date 11/07/14) yet but in order for this to work, this issue needs to be resolved:

http://issues.umbraco.org/issue/U4-5208

There is a work around in this project which you will need to enable with an AppSetting if you are not using 7.1.5+ or 6.2.2+

    <add key="UmbracoIdentity:UseAsyncActionInvokerFix" value="true"/>

This project is built against .Net 4.5.1

## Installation

First, read the minimum requirements above as you might need to enable the work around.

### Config updates

Remove FormsAuthentication from your web.config, this should be the last entry in your httpmodules lists:

    <remove name="FormsAuthenticationModule" />
    
You then need to disable FormsAuthentication as the authentication provider, change the authentication element to:

    <authentication mode="None" />
    
Replace the 'type' attribute of your UmbracoMembershipProvider in your web.config to be:

    "UmbracoIdentity.IdentityEnabledMembersMembershipProvider, UmbracoIdentity"
    
### Owin setup

**STOP!!** If you are not familiar with OWIN or ASP.Net Identity you will need to stop here and familiarize yourself with these things. If you are running the latest version of Visual Studio 2013, then you can create a new web project and create a site that has authentication. This will give you a good example of how to setup OWIN and Authentication. The 'light reading' link above also has tons of information.

If you are familiar then here's what to do... 

Once you've installed the Nuget package, you will see some classes added to your App_Startup folder:

* UmbracoApplicationUser - this is similar to the ApplicationUser class that comes with the VS 2013 template, except that this one inherits from UmbracoIdentityUser. You can customize this how you like.
* UmbracoStartup - this is basically the same as the Startup class that comes with the the VS 2013 template, except that it is named UmbracoStartup and contains some slightly different extension method calls:

        //Single method to configure the Identity user manager for use with Umbraco
        app.ConfigureUserManagerForUmbraco<UmbracoApplicationUser>();
        
        //Ensure owin is configured for Umbraco back office authentication
        app.UseUmbracoBackAuthentication();

    * The rest of the startup class is pretty much the same as the VS 2013 template except that you are using your UmbracoApplicationUser type and the UmbracoMembersUserManager class.

## [Documentation](https://github.com/Shandem/UmbracoIdentity/wiki)

See docs for examples, usage, etc...
