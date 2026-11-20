-- ============================================================================
-- PHẦN 1: KHỞI TẠO EXTENSIONS & ENUM TYPES
-- ============================================================================
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

CREATE TYPE channel_type AS ENUM ('WEB_SIGNALR', 'EMAIL', 'SMS', 'PUSH');

CREATE TYPE campaign_status AS ENUM (
    'DRAFT',       -- Bản nháp
    'SCHEDULED',   -- Đã hẹn lịch
    'PROCESSING',  -- Đang xử lý gửi
    'COMPLETED',   -- Hoàn thành
    'CANCELLED',   -- Đã hủy
    'FAILED'       -- Lỗi nghiêm trọng
);

CREATE TYPE delivery_status AS ENUM (
    'PENDING',     -- Chờ trong hàng đợi
    'SENT',        -- Đã gửi thành công
    'FAILED',      -- Gửi thất bại
    'READ'         -- Người dùng đã đọc
);

-- ============================================================================
-- PHẦN 2: TẠO CẤU TRÚC BẢNG
-- ============================================================================
CREATE TABLE roles (
    id SERIAL PRIMARY KEY,
    code VARCHAR(50) UNIQUE NOT NULL,
    name VARCHAR(100) NOT NULL,
    description TEXT
);

CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    username VARCHAR(100) UNIQUE NOT NULL,
    email VARCHAR(255) UNIQUE NOT NULL,
    phone_number VARCHAR(20),
    password_hash TEXT NOT NULL,
    full_name VARCHAR(150) NOT NULL,
    is_active BOOLEAN DEFAULT TRUE,
    notification_preferences JSONB DEFAULT '{"WEB_SIGNALR": true, "EMAIL": true, "SMS": false}'::jsonb,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE user_roles (
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    role_id INT REFERENCES roles(id) ON DELETE CASCADE,
    assigned_by UUID REFERENCES users(id) ON DELETE SET NULL,
    assigned_at TIMESTAMPTZ DEFAULT NOW(),
    PRIMARY KEY (user_id, role_id)
);

CREATE TABLE system_settings (
    key VARCHAR(100) PRIMARY KEY,
    value JSONB NOT NULL,
    description TEXT,
    updated_by UUID REFERENCES users(id) ON DELETE SET NULL,
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE notification_templates (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    code VARCHAR(100) UNIQUE NOT NULL,
    name VARCHAR(150) NOT NULL,
    channel channel_type NOT NULL,
    subject_template TEXT,
    body_template TEXT NOT NULL,
    is_active BOOLEAN DEFAULT TRUE,
    created_by UUID REFERENCES users(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE groups (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    code VARCHAR(100) UNIQUE NOT NULL,
    name VARCHAR(150) NOT NULL,
    description TEXT,
    is_public BOOLEAN DEFAULT TRUE,
    created_by UUID REFERENCES users(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE user_groups (
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    group_id UUID REFERENCES groups(id) ON DELETE CASCADE,
    is_muted BOOLEAN DEFAULT FALSE,
    joined_at TIMESTAMPTZ DEFAULT NOW(),
    PRIMARY KEY (user_id, group_id)
);

CREATE TABLE campaigns (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    title VARCHAR(255) NOT NULL,
    template_id UUID REFERENCES notification_templates(id) ON DELETE SET NULL,
    custom_subject TEXT,
    custom_body TEXT NOT NULL,
    template_variables JSONB DEFAULT '{}'::jsonb,
    channels channel_type[] NOT NULL,
    target_group_ids UUID[] DEFAULT '{}',
    target_user_ids UUID[] DEFAULT '{}',
    scheduled_at TIMESTAMPTZ,
    started_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ,
    status campaign_status DEFAULT 'DRAFT',
    total_recipients INT DEFAULT 0,
    pending_count INT DEFAULT 0,
    sent_count INT DEFAULT 0,
    failed_count INT DEFAULT 0,
    created_by UUID REFERENCES users(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE notification_deliveries (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    campaign_id UUID REFERENCES campaigns(id) ON DELETE CASCADE,
    recipient_id UUID REFERENCES users(id) ON DELETE CASCADE,
    channel channel_type NOT NULL,
    rendered_subject TEXT,
    rendered_body TEXT NOT NULL,
    status delivery_status DEFAULT 'PENDING',
    error_message TEXT,
    is_read BOOLEAN DEFAULT FALSE,
    read_at TIMESTAMPTZ,
    sent_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE audit_logs (
    id BIGSERIAL PRIMARY KEY,
    actor_id UUID REFERENCES users(id) ON DELETE SET NULL,
    action VARCHAR(100) NOT NULL,
    entity_type VARCHAR(50) NOT NULL,
    entity_id VARCHAR(100),
    details JSONB,
    ip_address INET,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================================
-- PHẦN 3: INDEXES & TRIGGER TỰ ĐỘNG CẬP NHẬT TIẾN ĐỘ
-- ============================================================================
CREATE INDEX idx_campaigns_schedule ON campaigns(status, scheduled_at) WHERE status = 'SCHEDULED';
CREATE INDEX idx_deliveries_pending ON notification_deliveries(campaign_id, status) WHERE status = 'PENDING';
CREATE INDEX idx_deliveries_recipient_history ON notification_deliveries(recipient_id, created_at DESC);
CREATE INDEX idx_deliveries_unread ON notification_deliveries(recipient_id, is_read) WHERE is_read = FALSE;
CREATE INDEX idx_audit_logs_created_at ON audit_logs(created_at DESC);

CREATE OR REPLACE FUNCTION update_campaign_progress()
RETURNS TRIGGER AS $$
BEGIN
    IF OLD.status IS DISTINCT FROM NEW.status THEN
        UPDATE campaigns
        SET 
            pending_count = pending_count 
                - (CASE WHEN OLD.status = 'PENDING' THEN 1 ELSE 0 END)
                + (CASE WHEN NEW.status = 'PENDING' THEN 1 ELSE 0 END),
            sent_count = sent_count 
                - (CASE WHEN OLD.status IN ('SENT', 'READ') THEN 1 ELSE 0 END)
                + (CASE WHEN NEW.status IN ('SENT', 'READ') THEN 1 ELSE 0 END),
            failed_count = failed_count 
                - (CASE WHEN OLD.status = 'FAILED' THEN 1 ELSE 0 END)
                + (CASE WHEN NEW.status = 'FAILED' THEN 1 ELSE 0 END)
        WHERE id = NEW.campaign_id;

        UPDATE campaigns
        SET status = 'COMPLETED', completed_at = NOW()
        WHERE id = NEW.campaign_id 
          AND pending_count = 0 
          AND status = 'PROCESSING';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_delivery_status_changed
AFTER UPDATE OF status ON notification_deliveries
FOR EACH ROW
EXECUTE FUNCTION update_campaign_progress();

-- ============================================================================
-- PHẦN 4: CHÈN DỮ LIỆU MẪU (SEED DATA)
-- ============================================================================

-- 1. Vai trò (Roles)
INSERT INTO roles (id, code, name, description) VALUES
(1, 'ADMIN', 'Quản trị viên hệ thống', 'Toàn quyền cấu hình, quản lý user, template, group và xem log'),
(2, 'SENDER', 'Điều phối viên gửi tin', 'Tạo chiến dịch, hẹn lịch gửi và theo dõi tiến độ'),
(3, 'RECIPIENT', 'Người nhận thông báo', 'Đăng ký nhóm, nhận thông báo và xem lịch sử');

-- 2. Người dùng (Users: 1 Admin, 1 Sender, 3 Recipients)
INSERT INTO users (id, username, email, phone_number, password_hash, full_name, notification_preferences) VALUES
('11111111-1111-1111-1111-111111111111', 'admin_sys', 'admin@company.vn', '0901000001', '$2a$12$hashedpassword_admin', 'Nguyễn Quản Trị', '{"WEB_SIGNALR": true, "EMAIL": true, "SMS": true}'),
('22222222-2222-2222-2222-222222222222', 'sender_lan', 'lan.operator@company.vn', '0901000002', '$2a$12$hashedpassword_sender', 'Trần Thị Lan (Điều phối)', '{"WEB_SIGNALR": true, "EMAIL": true, "SMS": false}'),
('33333333-3333-3333-3333-333333333333', 'user_minh', 'minh.dev@gmail.com', '0912345678', '$2a$12$hashedpassword_user1', 'Lê Hoàng Minh', '{"WEB_SIGNALR": true, "EMAIL": true, "SMS": true}'),
('44444444-4444-4444-4444-444444444444', 'user_hoa', 'hoa.nguyen@gmail.com', '0987654321', '$2a$12$hashedpassword_user2', 'Phạm Thu Hoa', '{"WEB_SIGNALR": true, "EMAIL": false, "SMS": false}'),
('55555555-5555-5555-5555-555555555555', 'user_nam', 'nam.invalid_email@test.local', '0933445566', '$2a$12$hashedpassword_user3', 'Đỗ Văn Nam', '{"WEB_SIGNALR": true, "EMAIL": true, "SMS": false}');

-- 3. Gán quyền (User Roles)
INSERT INTO user_roles (user_id, role_id, assigned_by) VALUES
('11111111-1111-1111-1111-111111111111', 1, '11111111-1111-1111-1111-111111111111'),
('22222222-2222-2222-2222-222222222222', 2, '11111111-1111-1111-1111-111111111111'),
('33333333-3333-3333-3333-333333333333', 3, '11111111-1111-1111-1111-111111111111'),
('44444444-4444-4444-4444-444444444444', 3, '11111111-1111-1111-1111-111111111111'),
('55555555-5555-5555-5555-555555555555', 3, '11111111-1111-1111-1111-111111111111');

-- 4. Cấu hình hệ thống (System Settings)
INSERT INTO system_settings (key, value, description, updated_by) VALUES
('RATE_LIMIT_PER_MINUTE', '{"email": 500, "sms": 100, "signalr": 5000}', 'Giới hạn số lượng thông báo gửi tối đa mỗi phút theo kênh', '11111111-1111-1111-1111-111111111111'),
('SMTP_CONFIG', '{"host": "smtp.gmail.com", "port": 587, "sender_name": "Hệ Thống Thông Báo"}', 'Cấu hình máy chủ gửi Email', '11111111-1111-1111-1111-111111111111'),
('RETRY_POLICY', '{"max_retries": 3, "backoff_seconds": 30}', 'Cấu hình thử lại khi gửi tin thất bại', '11111111-1111-1111-1111-111111111111');

-- 5. Mẫu thông báo (Notification Templates)
INSERT INTO notification_templates (id, code, name, channel, subject_template, body_template, created_by) VALUES
('aaaa1111-1111-1111-1111-111111111111', 'TPL_MAINTENANCE_WEB', 'Mẫu thông báo bảo trì (Web)', 'WEB_SIGNALR', 'Thông báo bảo trì hệ thống', 'Xin chào {{full_name}}, hệ thống sẽ bảo trì vào lúc {{time}} ngày {{date}}. Vui lòng lưu lại công việc.', '11111111-1111-1111-1111-111111111111'),
('aaaa2222-2222-2222-2222-222222222222', 'TPL_MAINTENANCE_EMAIL', 'Mẫu thông báo bảo trì (Email)', 'EMAIL', '[Quan trọng] Lịch bảo trì định kỳ ngày {{date}}', '<p>Chào <b>{{full_name}}</b>,</p><p>Hệ thống tạm ngưng hoạt động từ <b>{{time}}</b> để nâng cấp máy chủ.</p>', '11111111-1111-1111-1111-111111111111'),
('aaaa3333-3333-3333-3333-333333333333', 'TPL_EVENT_WEB', 'Mẫu mời tham gia sự kiện', 'WEB_SIGNALR', 'Sự kiện mới: {{event_name}}', 'Chào {{full_name}}, đừng bỏ lỡ sự kiện {{event_name}} diễn ra vào {{date}}!', '11111111-1111-1111-1111-111111111111');

-- 6. Nhóm nhận thông báo (Groups / SignalR Topics)
INSERT INTO groups (id, code, name, description, is_public, created_by) VALUES
('bbbb1111-1111-1111-1111-111111111111', 'topic_system_alerts', 'Cảnh báo & Bảo trì hệ thống', 'Nhóm nhận thông báo khẩn cấp và lịch bảo trì từ Ban quản trị', TRUE, '11111111-1111-1111-1111-111111111111'),
('bbbb2222-2222-2222-2222-222222222222', 'topic_company_events', 'Sự kiện & Tin tức nội bộ', 'Cập nhật các hoạt động, hội thảo và tin tức mới nhất', TRUE, '11111111-1111-1111-1111-111111111111'),
('bbbb3333-3333-3333-3333-333333333333', 'topic_vip_members', 'Nhóm khách hàng VIP', 'Nhóm riêng tư do Admin thêm vào', FALSE, '11111111-1111-1111-1111-111111111111');

-- 7. Người dùng tham gia nhóm (User Groups - JoinGroup)
INSERT INTO user_groups (user_id, group_id, is_muted) VALUES
('33333333-3333-3333-3333-333333333333', 'bbbb1111-1111-1111-1111-111111111111', FALSE), -- Minh tham gia Bảo trì (Bật)
('33333333-3333-3333-3333-333333333333', 'bbbb2222-2222-2222-2222-222222222222', FALSE), -- Minh tham gia Sự kiện (Bật)
('44444444-4444-4444-4444-444444444444', 'bbbb1111-1111-1111-1111-111111111111', FALSE), -- Hoa tham gia Bảo trì (Bật)
('44444444-4444-4444-4444-444444444444', 'bbbb2222-2222-2222-2222-222222222222', TRUE),  -- Hoa tham gia Sự kiện (Nhưng đang Mute)
('55555555-5555-5555-5555-555555555555', 'bbbb1111-1111-1111-1111-111111111111', FALSE); -- Nam tham gia Bảo trì (Bật)

-- 8. Chiến dịch gửi thông báo (Campaigns)
-- Chiến dịch 1: Đã hoàn thành gửi (Gửi qua WEB_SIGNALR và EMAIL cho nhóm Bảo trì)
INSERT INTO campaigns (
    id, title, template_id, custom_subject, custom_body, template_variables, 
    channels, target_group_ids, scheduled_at, started_at, completed_at, status, 
    total_recipients, pending_count, sent_count, failed_count, created_by, created_at
) VALUES (
    'cccc1111-1111-1111-1111-111111111111',
    'Thông báo bảo trì máy chủ tháng 11',
    'aaaa1111-1111-1111-1111-111111111111',
    'Thông báo bảo trì hệ thống',
    'Xin chào {{full_name}}, hệ thống sẽ bảo trì vào lúc 23:00 ngày 22/11/2026. Vui lòng lưu lại công việc.',
    '{"time": "23:00", "date": "22/11/2026"}',
    ARRAY['WEB_SIGNALR', 'EMAIL']::channel_type[],
    ARRAY['bbbb1111-1111-1111-1111-111111111111']::uuid[],
    NULL,
    NOW() - INTERVAL '2 hours',
    NOW() - INTERVAL '1 hour 55 minutes',
    'COMPLETED',
    5, 0, 4, 1, -- Tổng 5 lượt gửi (3 Web + 2 Email vì Hoa tắt Email), 4 thành công, 1 lỗi
    '22222222-2222-2222-2222-222222222222',
    NOW() - INTERVAL '2 hours'
);

-- Chiến dịch 2: Đang hẹn lịch (Scheduled) gửi vào ngày mai
INSERT INTO campaigns (
    id, title, template_id, custom_subject, custom_body, template_variables, 
    channels, target_group_ids, scheduled_at, status, 
    total_recipients, pending_count, sent_count, failed_count, created_by, created_at
) VALUES (
    'cccc2222-2222-2222-2222-222222222222',
    'Mời tham dự Tech Talk AI 2026',
    'aaaa3333-3333-3333-3333-333333333333',
    'Sự kiện mới: Tech Talk AI 2026',
    'Chào {{full_name}}, đừng bỏ lỡ sự kiện Tech Talk AI 2026 diễn ra vào 25/11/2026!',
    '{"event_name": "Tech Talk AI 2026", "date": "25/11/2026"}',
    ARRAY['WEB_SIGNALR']::channel_type[],
    ARRAY['bbbb2222-2222-2222-2222-222222222222']::uuid[],
    NOW() + INTERVAL '1 day',
    'SCHEDULED',
    1, 1, 0, 0, -- Chỉ có Minh nhận vì Hoa đã mute nhóm này
    '22222222-2222-2222-2222-222222222222',
    NOW() - INTERVAL '10 minutes'
);

-- 9. Chi tiết gửi thông báo (Notification Deliveries)
INSERT INTO notification_deliveries (
    id, campaign_id, recipient_id, channel, rendered_subject, rendered_body, 
    status, error_message, is_read, read_at, sent_at, created_at
) VALUES
-- Của Minh (Web: Đã đọc, Email: Đã gửi)
('dddd1111-1111-1111-1111-111111111111', 'cccc1111-1111-1111-1111-111111111111', '33333333-3333-3333-3333-333333333333', 'WEB_SIGNALR', 
 'Thông báo bảo trì hệ thống', 'Xin chào Lê Hoàng Minh, hệ thống sẽ bảo trì vào lúc 23:00 ngày 22/11/2026. Vui lòng lưu lại công việc.', 
 'READ', NULL, TRUE, NOW() - INTERVAL '1 hour', NOW() - INTERVAL '1 hour 59 minutes', NOW() - INTERVAL '2 hours'),

('dddd2222-2222-2222-2222-222222222222', 'cccc1111-1111-1111-1111-111111111111', '33333333-3333-3333-3333-333333333333', 'EMAIL', 
 '[Quan trọng] Lịch bảo trì định kỳ ngày 22/11/2026', '<p>Chào <b>Lê Hoàng Minh</b>,</p><p>Hệ thống tạm ngưng hoạt động từ <b>23:00</b> để nâng cấp máy chủ.</p>', 
 'SENT', NULL, FALSE, NULL, NOW() - INTERVAL '1 hour 58 minutes', NOW() - INTERVAL '2 hours'),

-- Của Hoa (Web: Đã gửi nhưng chưa đọc; Email không gửi do Hoa tắt nhận Email)
('dddd3333-3333-3333-3333-333333333333', 'cccc1111-1111-1111-1111-111111111111', '44444444-4444-4444-4444-444444444444', 'WEB_SIGNALR', 
 'Thông báo bảo trì hệ thống', 'Xin chào Phạm Thu Hoa, hệ thống sẽ bảo trì vào lúc 23:00 ngày 22/11/2026. Vui lòng lưu lại công việc.', 
 'SENT', NULL, FALSE, NULL, NOW() - INTERVAL '1 hour 59 minutes', NOW() - INTERVAL '2 hours'),

-- Của Nam (Web: Đã gửi; Email: Thất bại do sai định dạng tên miền email)
('dddd4444-4444-4444-4444-444444444444', 'cccc1111-1111-1111-1111-111111111111', '55555555-5555-5555-5555-555555555555', 'WEB_SIGNALR', 
 'Thông báo bảo trì hệ thống', 'Xin chào Đỗ Văn Nam, hệ thống sẽ bảo trì vào lúc 23:00 ngày 22/11/2026. Vui lòng lưu lại công việc.', 
 'SENT', NULL, FALSE, NULL, NOW() - INTERVAL '1 hour 59 minutes', NOW() - INTERVAL '2 hours'),

('dddd5555-5555-5555-5555-555555555555', 'cccc1111-1111-1111-1111-111111111111', '55555555-5555-5555-5555-555555555555', 'EMAIL', 
 '[Quan trọng] Lịch bảo trì định kỳ ngày 22/11/2026', '<p>Chào <b>Đỗ Văn Nam</b>,</p><p>Hệ thống tạm ngưng hoạt động từ <b>23:00</b> để nâng cấp máy chủ.</p>', 
 'FAILED', 'SMTP Error 550: Domain test.local does not exist', FALSE, NULL, NULL, NOW() - INTERVAL '2 hours'),

-- Tin nhắn đang chờ (PENDING) thuộc Chiến dịch 2 (Hẹn lịch) cho Minh
('dddd6666-6666-6666-6666-666666666666', 'cccc2222-2222-2222-2222-222222222222', '33333333-3333-3333-3333-333333333333', 'WEB_SIGNALR', 
 'Sự kiện mới: Tech Talk AI 2026', 'Chào Lê Hoàng Minh, đừng bỏ lỡ sự kiện Tech Talk AI 2026 diễn ra vào 25/11/2026!', 
 'PENDING', NULL, FALSE, NULL, NULL, NOW() - INTERVAL '10 minutes');

-- 10. Nhật ký hệ thống (Audit Logs)
INSERT INTO audit_logs (actor_id, action, entity_type, entity_id, details, ip_address, created_at) VALUES
('11111111-1111-1111-1111-111111111111', 'UPDATE_SETTING', 'SETTING', 'RATE_LIMIT_PER_MINUTE', '{"old": 300, "new": 500}', '192.168.1.10', NOW() - INTERVAL '1 day'),
('33333333-3333-3333-3333-333333333333', 'JOIN_GROUP', 'GROUP', 'bbbb1111-1111-1111-1111-111111111111', '{"group_code": "topic_system_alerts"}', '14.161.22.45', NOW() - INTERVAL '5 hours'),
('22222222-2222-2222-2222-222222222222', 'CREATE_CAMPAIGN', 'CAMPAIGN', 'cccc1111-1111-1111-1111-111111111111', '{"title": "Thông báo bảo trì máy chủ tháng 11", "mode": "IMMEDIATE"}', '192.168.1.25', NOW() - INTERVAL '2 hours'),
('22222222-2222-2222-2222-222222222222', 'SCHEDULE_CAMPAIGN', 'CAMPAIGN', 'cccc2222-2222-2222-2222-222222222222', '{"title": "Mời tham dự Tech Talk AI 2026"}', '192.168.1.25', NOW() - INTERVAL '10 minutes');