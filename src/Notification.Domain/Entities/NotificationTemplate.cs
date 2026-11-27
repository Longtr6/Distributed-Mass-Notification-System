using System;
using System.Collections.Generic;

namespace Notification.Domain.Entities;

public partial class NotificationTemplate
{
    public Guid Id { get; set; }

    public string Code { get; set; } = null!;

    public string Name { get; set; } = null!;

    public string? SubjectTemplate { get; set; }

    public string BodyTemplate { get; set; } = null!;

    public bool? IsActive { get; set; }

    public Guid? CreatedBy { get; set; }

    public DateTime? CreatedAt { get; set; }

    public DateTime? UpdatedAt { get; set; }

    public virtual ICollection<Campaign> Campaigns { get; set; } = new List<Campaign>();

    public virtual User? CreatedByNavigation { get; set; }
}
