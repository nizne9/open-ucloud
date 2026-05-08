use open_cloud_api::{
    AssignmentDetailResponse, AssignmentResource, AssignmentStatus, AssignmentSubmitResponse,
    AssignmentSummary, AssignmentUploadResponse, AttendanceQrPayload, AttendanceStatusResponse,
    AuthErrorCode, AuthErrorResponse, AuthFinishResponse, AuthSessionResponse,
    CourseActivityResponse, CourseDetailResponse, CourseListResponse, CourseResourceDetail,
    CourseResourceDownloadResponse, CourseResourceSummary, CourseSite, GoingSite, RoleInfo,
    RoleName, SessionUser,
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
fn serializes_attendance_qr_payload_without_tokens() {
    let response = AttendanceQrPayload {
        attendance_id: "attendance-1".to_string(),
        site_id: "site-1".to_string(),
        create_time: "2026-05-08+09:30:00".to_string(),
        class_lesson_id: "group-1".to_string(),
    };

    let json = serde_json::to_value(response).expect("attendance qr payload serializes");

    assert_eq!(json["attendanceId"], "attendance-1");
    assert_eq!(json["siteId"], "site-1");
    assert_eq!(json["createTime"], "2026-05-08+09:30:00");
    assert_eq!(json["classLessonId"], "group-1");
    assert!(json.get("accessToken").is_none());
    assert!(json.get("refreshToken").is_none());
}

#[test]
fn serializes_assignment_summary_and_detail_without_tokens() {
    let summary = AssignmentSummary {
        end_time: "2026-05-03 23:59:59".to_string(),
        id: "work-1".to_string(),
        site_id: "site-1".to_string(),
        site_name: "软件测试".to_string(),
        source: "course".to_string(),
        start_time: "2026-05-01 08:00:00".to_string(),
        status: AssignmentStatus::Pending,
        title: "实验报告".to_string(),
    };
    let detail = AssignmentDetailResponse {
        class_name: "2024 级 1 班".to_string(),
        comment: "写得不错".to_string(),
        content: "完成实验报告。".to_string(),
        end_time: summary.end_time.clone(),
        id: summary.id.clone(),
        is_overtime_commit: false,
        score: Some(95.5),
        site_id: summary.site_id.clone(),
        site_name: summary.site_name.clone(),
        start_time: summary.start_time.clone(),
        status: AssignmentStatus::Submitted,
        submitted_at: "2026-05-02 10:00:00".to_string(),
        submitted_attachments: vec![AssignmentResource {
            ext: Some("pdf".to_string()),
            name: "report.pdf".to_string(),
            preview_url: Some("https://files.example/report".to_string()),
            resource_id: "resource-1".to_string(),
            storage_id: Some("storage-1".to_string()),
        }],
        submitted_content: "已提交。".to_string(),
        teacher_resources: Vec::new(),
        title: summary.title,
    };

    let json = serde_json::to_value(detail).expect("assignment detail serializes");

    assert_eq!(json["id"], "work-1");
    assert_eq!(json["status"], "submitted");
    assert_eq!(json["submittedAttachments"][0]["resourceId"], "resource-1");
    assert!(json.get("accessToken").is_none());
    assert!(json.get("refreshToken").is_none());
}

#[test]
fn serializes_assignment_upload_and_submit_without_tokens() {
    let upload = AssignmentUploadResponse {
        assignment_id: "work-1".to_string(),
        file_name: "report.pdf".to_string(),
        preview_url: Some("https://files.example/report".to_string()),
        resource_id: "resource-1".to_string(),
        site_id: "site-1".to_string(),
        site_name: "软件测试".to_string(),
    };
    let submit = AssignmentSubmitResponse { ok: true };

    let upload_json = serde_json::to_value(upload).expect("upload response serializes");
    let submit_json = serde_json::to_value(submit).expect("submit response serializes");

    assert_eq!(upload_json["assignmentId"], "work-1");
    assert_eq!(upload_json["fileName"], "report.pdf");
    assert_eq!(upload_json["resourceId"], "resource-1");
    assert_eq!(upload_json["siteId"], "site-1");
    assert_eq!(submit_json["ok"], true);
    assert!(upload_json.get("accessToken").is_none());
    assert!(submit_json.get("refreshToken").is_none());
}

#[test]
fn serializes_course_resource_contract_without_tokens() {
    let detail = CourseResourceDetail {
        description: Some("实验资料".to_string()),
        download_url: Some("https://files.example/resource".to_string()),
        ext: Some("pdf".to_string()),
        name: "课件.pdf".to_string(),
        resource_id: "resource-1".to_string(),
        site_id: "site-1".to_string(),
        site_name: "软件测试".to_string(),
        size_bytes: Some(1024),
        updated_at: "2026-05-02 10:00:00".to_string(),
    };
    let summary = CourseResourceSummary {
        ext: detail.ext.clone(),
        name: detail.name.clone(),
        resource_id: detail.resource_id.clone(),
        site_id: detail.site_id.clone(),
        site_name: detail.site_name.clone(),
        size_bytes: detail.size_bytes,
        updated_at: detail.updated_at.clone(),
    };
    let download = CourseResourceDownloadResponse {
        records: vec![detail.clone()],
        written_paths: vec!["/tmp/课件.pdf".to_string()],
    };

    let summary_json = serde_json::to_value(summary).expect("resource summary serializes");
    let detail_json = serde_json::to_value(detail).expect("resource detail serializes");
    let download_json = serde_json::to_value(download).expect("download response serializes");

    assert_eq!(summary_json["resourceId"], "resource-1");
    assert_eq!(detail_json["downloadUrl"], "https://files.example/resource");
    assert_eq!(download_json["writtenPaths"][0], "/tmp/课件.pdf");
    assert!(detail_json.get("accessToken").is_none());
    assert!(download_json.get("refreshToken").is_none());
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
