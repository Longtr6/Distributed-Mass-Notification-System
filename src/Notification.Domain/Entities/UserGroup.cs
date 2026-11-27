using System;
using System.Collections.Generic;

namespace Notification.Domain.Entities;

public partial class UserGroup
{
    public Guid UserId { get; set; }

    public Guid GroupId { get; set; }

    public bool? IsMuted { get; set; }

    public DateTime? JoinedAt { get; set; }

    public virtual Group Group { get; set; } = null!;

    public virtual User User { get; set; } = null!;
}
