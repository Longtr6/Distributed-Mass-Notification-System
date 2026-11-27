using System;
using System.Collections.Generic;

namespace Notification.Domain.Entities;

public partial class Campaign
{
    public Guid Id { get; set; }

    public string Title { get; set; } = null!;

    public Guid? TemplateId { get; set; }

    public string? CustomSubject { get; set; }

    public string CustomBody { get; set; } = null!;

    public string? TemplateVariables { get; set; }

    public List<Guid>? TargetGroupIds { get; set; }

    public List<Guid>? TargetUserIds { get; set; }

    public DateTime? ScheduledAt { get; set; }

    public DateTime? StartedAt { get; set; }

    public DateTime? CompletedAt { get; set; }

    public int? TotalRecipients { get; set; }

    public int? PendingCount { get; set; }

    public int? SentCount { get; set; }

    public int? FailedCount { get; set; }

    public Guid? CreatedBy { get; set; }

    public DateTime? CreatedAt { get; set; }

    public virtual User? CreatedByNavigation { get; set; }

    public virtual ICollection<NotificationDelivery> NotificationDeliveries { get; set; } = new List<NotificationDelivery>();

    public virtual NotificationTemplate? Template { get; set; }
}
