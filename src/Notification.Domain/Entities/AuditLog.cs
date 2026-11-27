using System;
using System.Collections.Generic;
using System.Net;

namespace Notification.Domain.Entities;

public partial class AuditLog
{
    public long Id { get; set; }

    public Guid? ActorId { get; set; }

    public string Action { get; set; } = null!;

    public string EntityType { get; set; } = null!;

    public string? EntityId { get; set; }

    public string? Details { get; set; }

    public IPAddress? IpAddress { get; set; }

    public DateTime? CreatedAt { get; set; }

    public virtual User? Actor { get; set; }
}
