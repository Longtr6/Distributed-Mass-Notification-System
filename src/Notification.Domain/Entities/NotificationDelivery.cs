using System;
using System.Collections.Generic;

namespace Notification.Domain.Entities;

public partial class NotificationDelivery
{
    public Guid Id { get; set; }

    public Guid? CampaignId { get; set; }

    public Guid? RecipientId { get; set; }

    public string? RenderedSubject { get; set; }

    public string RenderedBody { get; set; } = null!;

    public string? ErrorMessage { get; set; }

    public bool? IsRead { get; set; }

    public DateTime? ReadAt { get; set; }

    public DateTime? SentAt { get; set; }

    public DateTime? CreatedAt { get; set; }

    public virtual Campaign? Campaign { get; set; }

    public virtual User? Recipient { get; set; }
}
