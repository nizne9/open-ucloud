use open_cloud_api::{
    AttendanceStatusResponse, AuthErrorCode, AuthErrorResponse, AuthFinishResponse,
    AuthSessionResponse, CourseActivityResponse, CourseDetailResponse, CourseListResponse,
    CourseSite, GoingSite, RoleInfo, RoleName, SessionUser,
};

#[test]
fn serializes_auth_session_without_tokens() {
    let response = AuthSessionResponse {
        selected_role: RoleName::Student,
        user: SessionUser {
            account: "2024000000".to_string(),
            real_name: "Alice".to_string(),
            user_id: "u-1".to_string(),
            user_name: "2024000000".to_string(),
        },
    };

    let json = serde_json::to_value(response).expect("session response serializes");

    assert_eq!(json["selectedRole"], "学生");
    assert_eq!(json["user"]["realName"], "Alice");
    assert!(json.get("accessToken").is_none());
    assert!(json.get("refreshToken").is_none());
}

#[test]
fn serializes_course_list_without_tokens() {
    let response = CourseListResponse {
        records: vec![CourseSite {
            id: "site-1".to_string(),
            site_name: "软件测试".to_string(),
        }],
    };

    let json = serde_json::to_value(response).expect("course list serializes");

    assert_eq!(json["records"][0]["id"], "site-1");
    assert_eq!(json["records"][0]["siteName"], "软件测试");
    assert!(json.get("accessToken").is_none());
    assert!(json.get("refreshToken").is_none());
}

#[test]
fn serializes_course_activity_without_tokens() {
    let response = CourseActivityResponse {
        records: vec![CourseSite {
            id: "site-1".to_string(),
            site_name: "软件测试".to_string(),
        }],
        going_sites: vec![GoingSite {
            group_id: "group-1".to_string(),
            site_id: "site-1".to_string(),
        }],
    };

    let json = serde_json::to_value(response).expect("course activity serializes");

    assert_eq!(json["records"][0]["siteName"], "软件测试");
    assert_eq!(json["goingSites"][0]["groupId"], "group-1");
    assert_eq!(json["goingSites"][0]["siteId"], "site-1");
    assert!(json.get("accessToken").is_none());
    assert!(json.get("refreshToken").is_none());
}

#[test]
fn serializes_course_detail_without_tokens() {
    let response = CourseDetailResponse {
        course: CourseSite {
            id: "site-1".to_string(),
            site_name: "软件测试".to_string(),
        },
        going_site: Some(GoingSite {
            group_id: "group-1".to_string(),
            site_id: "site-1".to_string(),
        }),
    };

    let json = serde_json::to_value(response).expect("course detail serializes");

    assert_eq!(json["course"]["id"], "site-1");
    assert_eq!(json["course"]["siteName"], "软件测试");
    assert_eq!(json["goingSite"]["groupId"], "group-1");
    assert!(json.get("accessToken").is_none());
    assert!(json.get("refreshToken").is_none());
}

#[test]
fn serializes_attendance_status_without_tokens() {
    let response = AttendanceStatusResponse {
        site_id: "site-1".to_string(),
        site_name: "软件测试".to_string(),
        going: true,
        group_id: Some("group-1".to_string()),
    };

    let json = serde_json::to_value(response).expect("attendance status serializes");

    assert_eq!(json["siteId"], "site-1");
    assert_eq!(json["siteName"], "软件测试");
    assert_eq!(json["going"], true);
    assert_eq!(json["groupId"], "group-1");
    assert!(json.get("accessToken").is_none());
    assert!(json.get("refreshToken").is_none());
}

#[test]
fn keeps_stable_auth_error_codes() {
    let response = AuthErrorResponse {
        code: AuthErrorCode::CaptchaInvalid,
        message: "验证码错误。".to_string(),
        retry_after_seconds: None,
    };

    let json = serde_json::to_value(response).expect("error response serializes");

    assert_eq!(json["code"], "CAPTCHA_INVALID");
    assert_eq!(json["message"], "验证码错误。");
}

#[test]
fn serializes_login_result_roles() {
    let response = AuthFinishResponse {
        roles: vec![RoleInfo {
            domain_id: "d".to_string(),
            domain_name: "教学空间".to_string(),
            id: "identity-1".to_string(),
            role_aliase: "学生".to_string(),
            role_id: "role-1".to_string(),
            role_name: RoleName::Student,
        }],
        selected_role: RoleName::Student,
        user: SessionUser {
            account: "2024000000".to_string(),
            real_name: "Alice".to_string(),
            user_id: "u-1".to_string(),
            user_name: "2024000000".to_string(),
        },
    };

    let json = serde_json::to_value(response).expect("finish response serializes");

    assert_eq!(json["roles"][0]["roleName"], "学生");
    assert_eq!(json["roles"][0]["domainName"], "教学空间");
}
