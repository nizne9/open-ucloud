use crate::HttpClient;

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct OpenCloudEndpoints {
    pub login_url: String,
    pub course_sites_url: String,
    pub going_sites_url: String,
    pub token_url: String,
    pub roles_url: String,
    pub ucloud_referer: String,
}

impl Default for OpenCloudEndpoints {
    fn default() -> Self {
        Self {
            login_url:
                "https://auth.bupt.edu.cn/authserver/login?service=https://ucloud.bupt.edu.cn"
                    .to_string(),
            course_sites_url: "https://apiucloud.bupt.edu.cn/ykt-site/site/list/student/current"
                .to_string(),
            going_sites_url: "https://apiucloud.bupt.edu.cn/blade-chat/web/chat/myCourse"
                .to_string(),
            token_url: "https://apiucloud.bupt.edu.cn/ykt-basics/oauth/token".to_string(),
            roles_url: "https://apiucloud.bupt.edu.cn/ykt-basics/userroledomaindept/listByUserId"
                .to_string(),
            ucloud_referer: "https://ucloud.bupt.edu.cn/".to_string(),
        }
    }
}

#[derive(Clone)]
pub struct OpenCloudClient<C> {
    pub(crate) endpoints: OpenCloudEndpoints,
    pub(crate) http: C,
}

impl<C> OpenCloudClient<C>
where
    C: HttpClient,
{
    pub fn new(http: C, endpoints: OpenCloudEndpoints) -> Self {
        Self { endpoints, http }
    }
}
